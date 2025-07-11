# Stage 1: base
FROM ubuntu:24.04 AS base

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Taipei

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install tzdata and clean up
RUN apt-get update && apt-get install -y --no-install-recommends \
    tzdata \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user with fixed UID/GID
ARG USERNAME=user
ARG UID=500
ARG GID=500
RUN groupadd --gid $GID $USERNAME \
    && useradd --uid $UID --gid $GID --create-home --shell /bin/bash $USERNAME \
    && usermod -aG sudo $USERNAME \
    && echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers

# Set working directory and switch to non-root user
USER $USERNAME
WORKDIR /home/$USERNAME

# Default command
CMD ["/bin/bash"]

# Stage 2: common_pkg_provider
FROM base AS common_pkg_provider
USER root

RUN apt-get update && apt-get install -y \
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

# Install Miniconda
RUN wget https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O miniconda.sh && \
    bash miniconda.sh -b -p /opt/conda && \
    rm miniconda.sh && \
    /opt/conda/bin/conda clean -ya

# Add conda to PATH
ENV PATH=/opt/conda/bin:$PATH

# Stage 3: verilator_provider
FROM common_pkg_provider AS verilator_provider
USER root

# Install Verilator build dependencies
RUN apt-get update && apt-get install -y \
    git \
    make \
    g++ \
    autoconf \
    automake \
    flex \
    bison \
    libfl-dev \
    libtool \
    perl \
    libperl-dev \
    zlib1g-dev \
    help2man \
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
FROM common_pkg_provider AS systemc_provider
USER root

# Install SystemC build dependencies
RUN apt-get update && apt-get install -y \
    libtool \
    autoconf \
    automake \
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

# Build and install SystemC
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

# Stage 5: last
FROM base AS last
USER root

# Install essential tools in the final stage
RUN apt-get update && apt-get install -y \
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

# Copy from common_pkg_provider with chown
COPY --from=common_pkg_provider --chown=user:user /opt/conda /opt/conda
ENV PATH=/opt/conda/bin:$PATH

# Copy from verilator_provider with chown
COPY --from=verilator_provider --chown=user:user /usr/local/bin/verilator /usr/local/bin/verilator
COPY --from=verilator_provider --chown=user:user /usr/local/share/verilator /usr/local/share/verilator

# Copy from systemc_provider with chown
COPY --from=systemc_provider --chown=user:user /opt/systemc /opt/systemc

# Set environment variables for SystemC (dynamically detect library path)
RUN mkdir -p /etc/profile.d && \
    if [ -d /opt/systemc/lib-linux64 ]; then \
        echo "export LD_LIBRARY_PATH=/opt/systemc/lib-linux64:\$LD_LIBRARY_PATH" >> /etc/profile.d/systemc.sh && \
        echo "export SYSTEMC_LDFLAGS=\"-L/opt/systemc/lib-linux64 -lsystemc\"" >> /etc/profile.d/systemc.sh; \
    elif [ -d /opt/systemc/lib-linux ]; then \
        echo "export LD_LIBRARY_PATH=/opt/systemc/lib-linux:\$LD_LIBRARY_PATH" >> /etc/profile.d/systemc.sh && \
        echo "export SYSTEMC_LDFLAGS=\"-L/opt/systemc/lib-linux -lsystemc\"" >> /etc/profile.d/systemc.sh; \
    elif [ -d /opt/systemc/lib ]; then \
        echo "export LD_LIBRARY_PATH=/opt/systemc/lib:\$LD_LIBRARY_PATH" >> /etc/profile.d/systemc.sh && \
        echo "export SYSTEMC_LDFLAGS=\"-L/opt/systemc/lib -lsystemc\"" >> /etc/profile.d/systemc.sh; \
    else \
        echo "Error: No SystemC library directory found"; exit 1; \
    fi
ENV SYSTEMC_HOME=/opt/systemc
ENV PATH=$SYSTEMC_HOME/bin:$PATH
ENV SYSTEMC_CXXFLAGS=-I$SYSTEMC_HOME/include

# Verify environment variables
RUN bash -c "source /etc/profile.d/systemc.sh && echo \$LD_LIBRARY_PATH && echo \$SYSTEMC_LDFLAGS"

# Set working directory and switch to non-root user
USER user
WORKDIR /home/user

# Source the environment variables for non-root user
RUN echo "source /etc/profile.d/systemc.sh" >> /home/user/.bashrc

# Default command
CMD ["/bin/bash", "-l"]