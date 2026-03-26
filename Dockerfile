ARG ARCH="amd64"
ARG OS="linux"
FROM quay.io/prometheus/busybox-${OS}-${ARCH}:latest
LABEL maintainer="The Prometheus Authors <prometheus-developers@googlegroups.com>"

ARG ARCH="amd64"
ARG OS="linux"
COPY .build/${OS}-${ARCH}/tendis_exporter /bin/tendis_exporter

EXPOSE      9104
USER        nobody
ENTRYPOINT  [ "/bin/tendis_exporter" ]
