ARG BASE_IMAGE
ARG BUILD_IMAGE

FROM ${BUILD_IMAGE} as build
WORKDIR /home/node
ADD package*.json ./
RUN npm install
ADD . .
RUN npm run build

FROM ${BUILD_IMAGE} as solidity-build
WORKDIR /home/node
ADD ./samples/solidity/package*.json ./
RUN npm install
ADD ./samples/solidity .
RUN npx hardhat compile

FROM alpine:3.19 AS SBOM
WORKDIR /
ADD . /SBOM
ADD ./.trivyignore /.trivyignore
RUN apk add --no-cache curl 
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v0.48.3
RUN trivy fs --format spdx-json --output /sbom.spdx.json /SBOM
RUN trivy sbom /sbom.spdx.json --severity UNKNOWN,HIGH,CRITICAL --exit-code 1

FROM $BASE_IMAGE
RUN mkdir -p /app/contracts/source \
    && chgrp -R 0 /app/ \
    && chmod -R g+rwX /app/ \
    && chown 1001:0 /app/contracts/source \
    && mkdir /.npm/ \
    && chgrp -R 0 /.npm/ \
    && chmod -R g+rwX /.npm/

WORKDIR /app/contracts/source
USER 1001
COPY --from=solidity-build --chown=1001:0 /home/node/contracts /home/node/package*.json ./
RUN npm install --production
WORKDIR /app/contracts
COPY --from=solidity-build --chown=1001:0 /home/node/artifacts/contracts/TokenFactory.sol/TokenFactory.json ./
# We also need to keep copying it to the old location to maintain compatibility with the FireFly CLI
COPY --from=solidity-build --chown=1001:0 /home/node/artifacts/contracts/TokenFactory.sol/TokenFactory.json /home/node/contracts/
WORKDIR /app
COPY --from=build --chown=1001:0 /home/node/dist ./dist
COPY --from=build --chown=1001:0 /home/node/package.json /home/node/package-lock.json ./
COPY --from=SBOM /sbom.spdx.json /sbom.spdx.json
COPY --from=SBOM /.trivyignore /.trivyignore

RUN npm install --production
EXPOSE 3000
CMD ["node", "dist/src/main"]
