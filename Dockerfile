# Stage 1: base image with Ubuntu 24.04 and construct conda_provider
FROM ubuntu:24.04 AS conda_provider

# Set non-interactive environment for apt
ENV DEBIAN_FRONTEND=noninteractive

# Set timezone to Asia/Taipei
ENV TZ=Asia/Taipei
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install tzdata and other essential tools
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    wget \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

ARG ARCH=x86_64
RUN if [ "$ARCH" = "x86_64" ]; then \
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh; \
    elif [ "$ARCH" = "aarch64" ]; then \
        wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-aarch64.sh -O miniconda.sh; \
    else \
        echo "Unsupported architecture: $ARCH"; exit 1; \
    fi
RUN bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh && \
    /opt/conda/bin/conda clean -ya

# Add conda to PATH
ENV PATH=/opt/conda/bin:$PATH

# Stage 2: common_pkg_provider
FROM ubuntu:24.04 AS common_pkg_provider
USER root

RUN apt-get update && apt-get install -y --no-install-recommends \
    vim \
    git \
    curl \
    wget \
    ca-certificates \
    build-essential \
    python3 \
    python3-pip \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Stage 3: verilator_provider
FROM ubuntu:24.04 AS verilator_provider
USER root

# Install Verilator build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    help2man \
    perl \
    python3 \
    python3-dev \
    python3-pip \
    make \
    build-essential \
    ca-certificates \
    autoconf \
    flex \
    bison \
    libfl2 \
    libfl-dev \
    libreadline-dev \
    zlib1g \
    zlib1g-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Clone and checkout Verilator source
RUN git clone https://github.com/verilator/verilator.git /tmp/verilator && \
    cd /tmp/verilator && \
    git checkout v5.024

# Configure Verilator
RUN cd /tmp/verilator && \
    autoconf && \
    ./configure

# Build and install Verilator
RUN cd /tmp/verilator && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/verilator

# Verify Verilator installation
RUN verilator --version

# Stage 4: systemc_provider
FROM ubuntu:24.04 AS systemc_provider
USER root

# Install SystemC build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    libtool \
    autoconf \
    automake \
    wget \
    ca-certificates \
    build-essential \
    cmake \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Download and extract SystemC
RUN cd /tmp && \
    wget https://github.com/accellera-official/systemc/archive/refs/tags/2.3.4.tar.gz -O systemc-2.3.4.tar.gz && \
    tar -xzf systemc-2.3.4.tar.gz && \
    cd systemc-2.3.4

# Configure SystemC
RUN cd /tmp/systemc-2.3.4 && \
    autoreconf -i && \
    mkdir build && cd build && \
    ../configure --prefix=/opt/systemc

# Build and install SystemC 2.3.4
RUN cd /tmp/systemc-2.3.4/build && \
    make -j$(nproc) && \
    make install && \
    rm -rf /tmp/systemc-2.3.4*

# Verify SystemC installation
RUN ls -l /opt/systemc/lib* && \
    test -f /opt/systemc/lib/libsystemc.so || \
    test -f /opt/systemc/lib-linux64/libsystemc.so || \
    test -f /opt/systemc/lib-linux/libsystemc.so || \
    { echo "Error: libsystemc.so not found in expected directories"; exit 1; }

# Stage 5: base
FROM ubuntu:24.04 AS base
USER root

# Define default username and group
ARG USERNAME="user"
ARG UID=1000
ARG GID=1000

# Create group if it doesn't exist
RUN if ! getent group ${GID} >/dev/null; then \
        groupadd -g ${GID} ${USERNAME}; \
    fi

# Create user with specified UID/GID, if UID is not already taken
RUN if ! id -u ${UID} >/dev/null 2>&1; then \
        useradd -m -s /bin/bash -u ${UID} -g ${GID} ${USERNAME}; \
    else \
        useradd -m -s /bin/bash -g ${GID} ${USERNAME}; \
    fi

# Install essential tools in the final stage
RUN apt-get update && apt-get install -y --no-install-recommends \
    vim \
    git \
    curl \
    wget \
    ca-certificates \
    build-essential \
    python3 \
    python3-pip \
    && ln -s /usr/bin/python3 /usr/bin/python \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy from conda_provider with chown
COPY --from=conda_provider --chown=${USERNAME}:${USERNAME} /opt/conda /opt/conda
ENV PATH=/opt/conda/bin:$PATH

# Copy from verilator_provider with chown
COPY --from=verilator_provider --chown=${USERNAME}:${USERNAME} /usr/local/bin/verilator /usr/local/bin/verilator
COPY --from=verilator_provider --chown=${USERNAME}:${USERNAME} /usr/local/share/verilator /usr/local/share/verilator

# Copy from systemc_provider with chown
COPY --from=systemc_provider --chown=${USERNAME}:${USERNAME} /opt/systemc /opt/systemc

# Set environment variables for SystemC (dynamically detect library path)
RUN mkdir -p /etc/profile.d && \
    if [ -d /opt/systemc/lib-linux64 ]; then \
        echo "export LD_LIBRARY_PATH=/opt/systemc/lib-linux64:\$LD_LIBRARY_PATH" >> /etc/profile.d/systemc.sh && \
        echo "export SYSTEMC_LDFLAGS=\"-L/opt/systemc/lib-linux64 -lsystemc\"" >> /etc/profile.d/systemc.sh; \
    elif [ -d /opt/systemc/lib-linux ]; then \
        echo "export LD_LIBRARY_PATH=/opt/systemc/lib-linux:\$LD_LIBRARY_PATH" >> /etc/profile.d/systemc.sh && \
        echo "export SYSTEMC_LDFLAGS=\"-L/opt/systemc/lib-linux -lsystemc\"" >> /etc/profile.d/systemc.sh; \
    elif [ -d /opt/systemc/lib ]; then \
        echo "export LD_LIBRARY_PATH=/opt/systemc/lib:$LD_LIBRARY_PATH" >> /etc/profile.d/systemc.sh && \
        echo "export SYSTEMC_LDFLAGS=\"-L/opt/systemc/lib -lsystemc\"" >> /etc/profile.d/systemc.sh; \
    else \
        echo "Error: No SystemC library directory found"; exit 1; \
    fi

# Set additional environment variables
ENV SYSTEMC_HOME=/opt/systemc
ENV PATH=$SYSTEMC_HOME:/bin:$PATH
ENV SYSTEMC_CXXFLAGS=-I$SYSTEMC_HOME:/include

# Verify environment variables
RUN bash -c "source /etc/profile.d/systemc.sh && echo \$LD_LIBRARY_PATH && echo \$SYSTEMC_LDFLAGS"

# Set working directory and switch to non-root user
USER ${USERNAME}
WORKDIR /home/${USERNAME}

# Source the environment variables for non-root user
RUN echo "source /etc/profile.d/systemc.sh" >> /home/${USERNAME}/.bashrc

# Default command
CMD ["/bin/bash", "-l", "-c", "source /etc/profile.d/systemc.sh && exec /bin/bash -i"]