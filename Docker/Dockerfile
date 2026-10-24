# Ajaa paketoidun palvelimen. Rakenna projektin juuresta, kun Out/LinuxServer on olemassa:
#   docker build -f Docker/Dockerfile -t lumenkolaus-server .
FROM ubuntu:24.04

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --create-home --uid 10001 lumi

# Unreal ei suostu ajamaan palvelinta root-käyttäjänä.
COPY --chown=lumi:lumi Out/LinuxServer/ /server/
USER lumi
WORKDIR /server

EXPOSE 7777/udp
ENTRYPOINT ["/server/LumenKolausServer.sh", "/Game/Maps/Piha", "-log", "-port=7777"]
