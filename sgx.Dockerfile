ARG egover=1.5.0

FROM ghcr.io/edgelesssys/ego/build-base:v${egover} AS builder

ARG egover
ARG DEBIAN_FRONTEND=noninteractive
ARG VERSION

RUN apt-get update && apt-get install --yes --no-install-recommends \
        build-essential \
        ca-certificates \
        git \
        wget \
        libssl-dev \
        lsb-release \
    && rm -rf /var/lib/apt/lists/*

RUN egodeb=ego_${egover}_amd64_ubuntu-$(grep -oP 'VERSION_ID="\K[^"]+' /etc/os-release).deb \
  && wget https://github.com/edgelesssys/ego/releases/download/v${egover}/${egodeb} \
  && dpkg -i --force-depends ${egodeb}

# Build your app
# Cache for the modules
WORKDIR /build
COPY go.mod go.sum .
RUN --mount=type=cache,target=/root/.cache/go-build ego-go mod download

COPY . .
# NOTE: the -s ldflag removes the symbol table which causes issues with ego sign
#RUN --mount=type=cache,target=/root/.cache/go-build GOOS=linux ego-go build -trimpath -ldflags "-s -X cmd.Version=$VERSION -X main.Version=$VERSION -linkmode external -extldflags '-static'" -v -o mev-boost-relay .
#RUN --mount=type=cache,target=/root/.cache/go-build GOOS=linux ego-go build -trimpath -ldflags "-X cmd.Version=$VERSION -X main.Version=$VERSION -linkmode external -extldflags '-static'" -v -o mev-boost-relay .
RUN --mount=type=cache,target=/root/.cache/go-build GOOS=linux ego-go build -trimpath -ldflags "-X cmd.Version=$VERSION -X main.Version=$VERSION" -v -o mev-boost-relay .

RUN --mount=type=secret,id=signingkey,dst=private.pem,required=true ego sign mev-boost-relay
#RUN ego bundle mev-boost-relay


# Use the deploy target if you want to deploy your app as a Docker image
FROM ghcr.io/edgelesssys/ego-deploy:v${egover} AS deploy
RUN apt-get update && apt-get install --yes --no-install-recommends \
        libstdc++ \
        libc6-compat \
    && rm -rf /var/lib/apt/lists/*
COPY --from=builder /build/mev-boost-relay /usr/local/bin/
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
ENTRYPOINT ["ego", "run", "/usr/local/bin/mev-boost-relay"]
