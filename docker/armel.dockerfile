FROM ev3dev/debian-stretch-armel-cross

RUN sudo apt-get update && \
    DEBIAN_FRONTEND=noninteractive sudo apt-get install --yes --no-install-recommends \
        cmake \
        libglib2.0-dev \
        pandoc \
        valac
