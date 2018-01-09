#!/bin/bash

# 工具环境变量
export FABRIC_CFG_PATH=${PWD}
export COMPOSE_PROJECT_NAME=fabriclab

# 打印帮助
function printHelp () {
  echo "使用说明："
  echo "  fabric-cli.sh -m start|stop|restart|clean|generate [-c <channel>] [-t <timeout>] [-d <delay>] [-f <docker-compose-file>]"
  echo "  fabric-cli.sh -h|--help (print this message)"
  echo "    -m <mode> - 子命令有 'start', 'stop', 'restart', 'clean' 或 'create'"
  echo "      - 'start' - 启动网络服务"
  echo "      - 'stop' - 停止网络服务"
  echo "      - 'restart' - 重启网络服务"
  echo "      - 'clean' - 清理/删除网络服务"
  echo "      - 'create' - 生成所需的网络服务、证书以及创世块"
  echo "    -c <channel> - 要使用的通道名 (默认为 \"channel_lab\")"
  echo "    -t <timeout> - 命令超时时间，单位：秒 (默认为 10)"
  echo "    -d <delay> - 命令延时等待时间，单位：秒 (默认为 3)"
  echo "    -f <docker-compose-file> - 指定要使用的 docker-compose 文件 (默认为 \"docker-compose.yaml\")"
  echo
}

function confirm () {
  read -p "是否继续 (y/n)? " ans
  case "$ans" in
    y|Y )
      echo "继续 ..."
    ;;
    n|N )
      echo "退出..."
      exit 1
    ;;
    * )
      confirm
    ;;
  esac
}

# 生成证书
function generateCerts (){
  which cryptogen
  if [ "$?" -ne 0 ]; then
    echo "cryptogen tool not found. exiting"
    exit 1
  fi
  echo
  echo "##########################################################"
  echo "##### Generate certificates using cryptogen tool #########"
  echo "##########################################################"
  if [ -d "crypto-config" ]; then
    rm -Rf crypto-config
  fi
  cryptogen generate --config=./crypto-config.yaml
  if [ "$?" -ne 0 ]; then
    echo "Failed to generate certificates..."
    exit 1
  fi
  echo
}

# 生成创世块、通道交易配置以及节点更新交易
function generateChannelArtifacts() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo "configtxgen tool not found. exiting"
    exit 1
  fi

  if [ ! -d "channel-artifacts" ]; then
    mkdir channel-artifacts
  fi

  echo "##########################################################"
  echo "#########  Generating Orderer Genesis block ##############"
  echo "##########################################################"
  configtxgen -profile OrdererGenesis -outputBlock ./channel-artifacts/genesis.block
  if [ "$?" -ne 0 ]; then
    echo "Failed to generate orderer genesis block..."
    exit 1
  fi
  echo
  echo "#################################################################"
  echo "### Generating channel configuration transaction 'channel.tx' ###"
  echo "#################################################################"
  configtxgen -profile OrgsChannel -outputCreateChannelTx ./channel-artifacts/channel.tx -channelID $CHANNEL_NAME
  if [ "$?" -ne 0 ]; then
    echo "Failed to generate channel configuration transaction..."
    exit 1
  fi

  for OrgMSP in Bank1MSP Owner1MSP Storage1MSP Supervisor1MSP; do
    echo
    echo "#################################################################"
    echo "#######    Generating anchor peer update for ${OrgMSP}   ##########"
    echo "#################################################################"
    configtxgen -profile OrgsChannel -outputAnchorPeersUpdate ./channel-artifacts/${OrgMSP}anchors.tx -channelID $CHANNEL_NAME -asOrg ${OrgMSP}
    if [ "$?" -ne 0 ]; then
      echo "Failed to generate anchor peer update for ${OrgMSP}..."
      exit 1
    fi
  done

  echo
}

function replacePrivateKey () {
  # MaxOSX 特殊
  ARCH=`uname -s | grep Darwin`
  if [ "$ARCH" == "Darwin" ]; then
    OPTS="-it"
  else
    OPTS="-i"
  fi

  cp template.yaml $COMPOSE_FILE

  CURRENT_DIR=$PWD

  cd crypto-config/peerOrganizations/bank1.samples.cn/ca/
  PRIV_KEY=$(ls *_sk)
  cd "$CURRENT_DIR"
  sed $OPTS "s/CA_BANK1_PRIVATE_KEY/${PRIV_KEY}/g" $COMPOSE_FILE

  cd crypto-config/peerOrganizations/owner1.samples.cn/ca/
  PRIV_KEY=$(ls *_sk)
  cd "$CURRENT_DIR"
  sed $OPTS "s/CA_OWNER1_PRIVATE_KEY/${PRIV_KEY}/g" $COMPOSE_FILE

  cd crypto-config/peerOrganizations/storage1.samples.cn/ca/
  PRIV_KEY=$(ls *_sk)
  cd "$CURRENT_DIR"
  sed $OPTS "s/CA_STORAGE1_PRIVATE_KEY/${PRIV_KEY}/g" $COMPOSE_FILE

  cd crypto-config/peerOrganizations/supervisor1.samples.cn/ca/
  PRIV_KEY=$(ls *_sk)
  cd "$CURRENT_DIR"
  sed $OPTS "s/CA_SUPERVISOR1_PRIVATE_KEY/${PRIV_KEY}/g" $COMPOSE_FILE

  # MaxOSX 特殊
  if [ "$ARCH" == "Darwin" ]; then
    rm -f ${COMPOSE_FILE}t
  fi
}

# 创建docker容器
function networkCreate () {
  CHANNEL_NAME=$CHANNEL_NAME TIMEOUT=$CLI_TIMEOUT DELAY=$CLI_DELAY docker-compose -f $COMPOSE_FILE up --no-start
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to create network"
    exit 1
  fi
}

function networkStart () {
    docker-compose -f $COMPOSE_FILE start
}

function networkStop () {
    docker-compose -f $COMPOSE_FILE stop
}

function networkClean () {
    if [ -a "$COMPOSE_FILE" ]; then
        docker-compose -f $COMPOSE_FILE down
        rm -f $COMPOSE_FILE
    fi

    if [ -d "channel-artifacts" ]; then
        rm -fr channel-artifacts
    fi

    if [ -d "crypto-config" ]; then
        rm -fr crypto-config
    fi

}


#######################
# 变量初始
OS_ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
CLI_TIMEOUT=10
CLI_DELAY=3
CHANNEL_NAME="channel_lab"
COMPOSE_FILE=docker-compose.yaml

# 读取参数
while getopts "h?m:c:t:d:f:" opt; do
  case "$opt" in
    h|\?)
      printHelp
      exit 0
    ;;
    m)  MODE=$OPTARG
    ;;
    c)  CHANNEL_NAME=$OPTARG
    ;;
    t)  CLI_TIMEOUT=$OPTARG
    ;;
    d)  CLI_DELAY=$OPTARG
    ;;
    f)  COMPOSE_FILE=$OPTARG
    ;;
  esac
done

if [ "$MODE" == "start" ]; then
  EXPMODE="Starting"
elif [ "$MODE" == "stop" ]; then
  EXPMODE="Stopping"
elif [ "$MODE" == "restart" ]; then
  EXPMODE="Restarting"
elif [ "$MODE" == "clean" ]; then
  EXPMODE="Cleaning"
elif [ "$MODE" == "create" ]; then
  EXPMODE="Creating network, certs and genesis block"
else
  printHelp
  exit 1
fi

echo "${EXPMODE} with channel '${CHANNEL_NAME}' and CLI timeout of '${CLI_TIMEOUT}'"

# confirm

# 执行子命令
if [ "${MODE}" == "create" ]; then
  networkClean
  generateCerts
  generateChannelArtifacts
  replacePrivateKey
  networkCreate
elif [ "${MODE}" == "start" ]; then
  networkStart
elif [ "${MODE}" == "stop" ]; then
  networkStop
elif [ "${MODE}" == "clean" ]; then
  networkStop
  networkClean
elif [ "${MODE}" == "restart" ]; then
  networkStop
  networkStart
else
  printHelp
  exit 1
fi
