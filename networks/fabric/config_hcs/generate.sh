#!/usr/bin/env bash

: "${FABRIC_VERSION:=2.0.0}"
: "${FABRIC_CA_VERSION:=1.4.6}"

if [ "$HEDERA_ACCOUNT_ID" = ""  -a  "$HEDERA_ACCOUNT_PRIVATE_KEY" = "" ]; then
    echo "must set HEDERA_ACCOUNT_ID and HEDERA_ACCOUNT_PRIVATE_KEY"
    exit 1
fi

# official binaries don't work for HCS, need to manually install the binaries & docker images atm
# if the binaries are not available, download them
#if [[ ! -d "bin" ]]; then
#  curl -sSL http://bit.ly/2ysbOFE | bash -s -- ${FABRIC_VERSION} ${FABRIC_CA_VERSION} 0.4.14 -ds
#fi

if [[  ! -x "bin/configtxgen" ]]; then
    echo "please build required hyperledger fabric binaries and docker images from pluggable-hcs repo"
    exit 1
fi

if [[ ! -x "bin/hcscli" ]]; then
    GO111MODULE=on GOBIN=$PWD/bin go get github.com/hashgraph/hcscli@v0.2.1
fi

sed -e 's/HEDERA_ACCOUNT_ID/'$HEDERA_ACCOUNT_ID'/' -e 's/HEDERA_ACCOUNT_PRIVATE_KEY/'$HEDERA_ACCOUNT_PRIVATE_KEY'/' \
    ./hedera_env_template.json  > ./hedera_env.json
OUTPUT=$(./bin/hcscli --config hedera_env.json topic create 2) || { echo "failed to create topics using hcscli!!!" && exit 1; }
TOPICS=($(echo $OUTPUT | grep -o '[0-9]\+\.[0-9\+\.[0-9]\+'))
echo "generated HCS topics: ${TOPICS[@]}"
sed -e 's/SYS_HCS_TOPIC_ID/'${TOPICS[0]}'/' -e 's/APP_HCS_TOPIC_ID/'${TOPICS[1]}'/' ./configtx-template.yaml > ./configtx.yaml

# orderer.yaml
sed -e 's/HEDERA_ACCOUNT_ID/'$HEDERA_ACCOUNT_ID'/' -e 's/HEDERA_ACCOUNT_PRIVATE_KEY/'$HEDERA_ACCOUNT_PRIVATE_KEY'/' \
    ./orderer-template.yaml  > ./orderer.yaml

rm -rf ./crypto-config/
rm -f ./genesis.block
rm -f ./mychannel.tx

./bin/cryptogen generate --config=./crypto-config.yaml
./bin/configtxgen -profile OrdererGenesis -outputBlock genesis.block -channelID syschannel
./bin/configtxgen -channelCreateTxBaseProfile OrdererGenesis -profile ChannelConfig -outputCreateChannelTx mychannel.tx -channelID mychannel

# Rename the key files we use to be key.pem instead of a uuid
for KEY in $(find crypto-config -type f -name "*_sk"); do
    KEY_DIR=$(dirname ${KEY})
    mv ${KEY} ${KEY_DIR}/key.pem
done
