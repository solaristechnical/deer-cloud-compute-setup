# Use an official Ruby base image (Modelkit relies heavily on Ruby)
FROM ruby:3.2-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# 1. INSTALL ENERGYPLUS (Example: v22.2.0)
# Adjust the version and URL based on what your templates require
ENV ENERGYPLUS_VERSION=22.2.0
ENV ENERGYPLUS_TAG=v22.2.0
ENV ENERGYPLUS_RELEASE_COMMIT=c249759bad
ENV ENERGYPLUS_SHA256=28fb4dd43756df92c02972b41af28d05cf0e44bbad5ee7822ae1b019120ea853
ENV ENERGYPLUS_FILENAME=EnergyPlus-${ENERGYPLUS_VERSION}-${ENERGYPLUS_RELEASE_COMMIT}-Linux-Ubuntu22.04-x86_64.sh

# Download, verify, and install EnergyPlus
RUN wget https://github.com/NREL/EnergyPlus/releases/download/${ENERGYPLUS_TAG}/${ENERGYPLUS_FILENAME} \
    && sha256sum ${ENERGYPLUS_FILENAME} | grep ${ENERGYPLUS_SHA256} \
    && chmod +x ${ENERGYPLUS_FILENAME} \
    && ./${ENERGYPLUS_FILENAME} --skip-license \
    && rm ${ENERGYPLUS_FILENAME}

# 2. INSTALL MODELKIT CLI
# Create a directory for Modelkit and download it.
# (Note: Replace this URL with the actual Linux CLI binary download link from Big Ladder)
WORKDIR /opt/modelkit
RUN curl -L -o modelkit.zip "https://download.bigladdersoftware.com/?ref=modelkit-catalyst-latest-mac" \
    && unzip modelkit.zip \
    && rm modelkit.zip \
    && ln -s /opt/modelkit/modelkit /usr/local/bin/modelkit

# Alternative copy method if URL download is restricted:
#COPY modelkit-linux.zip /opt/modelkit/
#RUN cd /opt/modelkit && unzip modelkit-linux.zip && rm modelkit-linux.zip

# 3. CONFIGURE MODELKIT ENGINE PATH
# Modelkit looks for a configuration file to know where EnergyPlus lives
WORKDIR /root
RUN echo "engine = '/usr/local/EnergyPlus-${ENERGYPLUS_VERSION//./-}'" > .modelkit-config

# Set up app workspace
WORKDIR /app

# Default command
CMD ["modelkit", "--version"]
