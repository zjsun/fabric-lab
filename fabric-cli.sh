#!/bin/bash

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
  echo "    -c <channel> - 要使用的通道名 (默认为 \"channel-01\")"
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

function replacePrivateKey () {
  # MaxOSX 特殊
  ARCH=`uname -s | grep Darwin`
  if [ "$ARCH" == "Darwin" ]; then
    OPTS="-it"
  else
    OPTS="-i"
  fi

  # Copy the template to the file that will be modified to add the private key
  cp docker-compose-e2e-template.yaml docker-compose-e2e.yaml

  # The next steps will replace the template's contents with the
  # actual values of the private key file names for the two CAs.
  CURRENT_DIR=$PWD
  cd crypto-config/peerOrganizations/org1.example.com/ca/
  PRIV_KEY=$(ls *_sk)
  cd "$CURRENT_DIR"
  sed $OPTS "s/CA1_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml
  cd crypto-config/peerOrganizations/org2.example.com/ca/
  PRIV_KEY=$(ls *_sk)
  cd "$CURRENT_DIR"
  sed $OPTS "s/CA2_PRIVATE_KEY/${PRIV_KEY}/g" docker-compose-e2e.yaml

  # MaxOSX 特殊
  if [ "$ARCH" == "Darwin" ]; then
    rm docker-compose-e2e.yamlt
  fi
}


#######################
# 变量初始
OS_ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
CLI_TIMEOUT=10
CLI_DELAY=3
CHANNEL_NAME="channel-01"
COMPOSE_FILE=docker-compose.yaml
COMPOSE_FILE_COUCH=docker-compose-couch.yaml

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
confirm

# 执行子命令
if [ "${MODE}" == "create" ]; then
  generateCerts
  replacePrivateKey
  generateChannelArtifacts
  networkCreate
elif [ "${MODE}" == "start" ]; then
  networkStart
elif [ "${MODE}" == "stop" ]; then
  networkStop
elif [ "${MODE}" == "clean" ]; then
  networkClean
elif [ "${MODE}" == "restart" ]; then
  networkStop
  networkStart
else
  printHelp
  exit 1
fi
