FROM registry.access.redhat.com/ubi9/nodejs-20 AS node-builder

USER root

RUN npm install --global yarn

WORKDIR /opt/app-root/src
USER default

RUN curl -L -o radarr.tar.gz $(curl -s https://api.github.com/repos/Radarr/Radarr/releases/latest | grep 'tarball_url' | cut -d '"' -f 4)

RUN mkdir radarr

RUN tar xvaf radarr.tar.gz -C radarr --strip-components=1

WORKDIR /opt/app-root/src/radarr

RUN sh build.sh --frontend

FROM registry.access.redhat.com/ubi9 AS dotnet-builder

USER root

RUN useradd dotnet -m -d /home/dotnet -s /sbin/nologin \
    && mkdir -p /app \
    && chown -R dotnet /app \
    && dnf update -y \
    && dnf install -y dotnet-sdk-6.0 xz

USER dotnet
WORKDIR /app

RUN export VERSION=$(curl -s https://api.github.com/repos/Radarr/Radarr/releases/latest | grep '"tag_name"' | sed 's/.*"tag_name": "\(.*\)",/\1/') \
  && echo $VERSION > version.txt

RUN curl -L -o radarr.tar.gz $(curl -s https://api.github.com/repos/Radarr/Radarr/releases/latest | grep 'tarball_url' | cut -d '"' -f 4)

RUN mkdir radarr

RUN tar xvaf radarr.tar.gz -C radarr --strip-components=1

RUN DOTNET_VERSION=$(dotnet --info | grep 'Version:' | head -1 | awk '{print $2}') && echo $DOTNET_VERSION > dotnet.version

RUN mkdir ffmpeg

RUN if [ $(dotnet --info | grep 'Architecture:' | awk '{print $2}') = "x64" ]; then ARCH="amd64"; else ARCH="arm64"; fi ; \
  curl -L https://johnvansickle.com/ffmpeg/releases/ffmpeg-release-$ARCH-static.tar.xz -o ffmpeg.tar.xz && \
  tar xvaf ffmpeg.tar.xz -C ffmpeg --strip-components=1

WORKDIR /app/radarr

#RUN sed -i "s/\"version\": \"[^\"]*\"/\"version\": \"$(cat ../dotnet.version)\"/" global.json
#RUN cat global.json

RUN sh build.sh --runtime linux-$(dotnet --info | grep 'Architecture:' | awk '{print $2}') --backend --package

RUN mv /app/radarr/_output/net6.0/linux-$(dotnet --info | grep 'Architecture:' | awk '{print $2}') /app/radarr/_output/net6.0/linux

FROM registry.access.redhat.com/ubi9-minimal

RUN microdnf install -y dotnet-runtime-6.0

COPY --from=dotnet-builder /app/radarr/_output/net6.0/linux /app/
COPY --from=node-builder /opt/app-root/src/radarr/_output/UI /app/UI

COPY --from=dotnet-builder /app/version.txt /version.txt
COPY --from=dotnet-builder /app/ffmpeg/ffprobe /app/ffprobe

RUN chown -R 1001:1001 /app

USER 1001

VOLUME /config

EXPOSE 8989/tcp

CMD [ "/app/Radarr", "-nobrowser", "-data=/config" ]
