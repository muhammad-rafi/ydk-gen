#!/bin/bash
#  -----------------------------------------------------------------------------
# Copyright 2020 Yan Gorelik, YDK Solutions
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ------------------------------------------------------------------------------
#
# Bash script to install ydk
#
# For usage run: ./install_ydk -h
# ------------------------------------------------------------------------------

function print_msg {
    echo -e "${MSG_COLOR}*** $(date) *** install_ydk.sh | $@ ${NOCOLOR}"
}

function run_cmd {
    local cmd=$@
    print_msg "Running: $cmd"
    $@
    local status=$?
    if [ $status -ne 0 ]; then
        MSG_COLOR=$RED
        print_msg "Exiting '$@' with status=$status"
        exit $status
    fi
    return $status
}

function usage {
    MSG_COLOR=$NOCOLOR
    echo "usage: install_ydk [-l [cpp, py, go]] [-s gnmi] [-h]"
    echo "Options and arguments:"
    echo "  -l [cpp, py, go, all] installation language; if not specified Python is assumed"
    echo "                        'all' corresponds to all available languages"
    echo "  -s gnmi               install gNMI service package;"
    echo "                        if not specified, only core packages are installed"
    echo "  -h|--help             print this help message and exit"
    echo " "
    echo "Environment variables:"
    echo "YDKGEN_HOME         specifies location of ydk-gen git repository;"
    echo "                    if not set, $HOME/ydk-gen is assumed"
    echo "GOROOT              specifies installation directory of go software;"
    echo "                    if not set, /usr/local/go is assumed"
    echo "GOPATH              specifies location of golang directory;"
    echo "                    if not set, $HOME/golang is assumed"
    echo "C_INCLUDE_PATH      location of C include files;"
    echo "                    if not set, /usr/local/include is assumed"
    echo "CPLUS_INCLUDE_PATH  location of C++ include files;"
    echo "                    if not set, /usr/local/include is assumed"
}

function check_python_installation {
  if [[ ! -d ${YDKGEN_HOME}/venv ]]; then
    print_msg "Creating Python3 virtual environment in ${YDKGEN_HOME}/venv"
    run_cmd python3 -m venv ${HOME}/venv
  fi
  run_cmd source ${HOME}/venv/bin/activate

  print_msg "Checking python version and installation"
  python --version
  status=$?
  if [ $status -ne 0 ]; then
    MSG_COLOR=$RED
    print_msg "Could not locate python3 interpretor"
    exit $status
  fi
  print_msg "Checking pip version and installation"
  pip -V
  status=$?
  if [ $status -ne 0 ]; then
    MSG_COLOR=$RED
    print_msg "Could not locate ${PIP_BIN}"
    exit $status
  fi
  print_msg "Python location: $(which ${PYTHON_BIN})"
  print_msg "Pip location: $(which ${PIP_BIN})"
}

function init_py_env {
  check_python_installation
  print_msg "Initializing Python requirements"
  pip install -r requirements.txt
  if [[ ${ydk_lang} == "py" || ${ydk_lang} == "all" ]]; then
    pip install pybind11
  fi
}

function init_go_env {
    print_msg "Initializing Go environment"

    if [[ $(uname) == "Darwin" ]]; then
        if [[ $GOPATH. == "." ]]; then
            export GOPATH=$HOME/golang"
        fi
        print_msg "GOROOT: $GOROOT"
        print_msg "GOPATH: $GOPATH"
    else
        if [[ $GOROOT. == "." ]]; then
            export GOROOT=/usr/local/go
            print_msg "Setting GOROOT to $GOROOT"
        else
            print_msg "GOROOT: $GOROOT"
        fi
        export PATH=$GOROOT/bin:$PATH

        if [[ $GOPATH. == "." ]]; then
            export GOPATH="$HOME/golang"
            mkdir -p $GOPATH
            print_msg "Setting GOPATH to $GOPATH"
        else
            print_msg "GOPATH: $GOPATH"
        fi
    fi
    go_version=$(echo `go version` | awk '{ print $3 }' | cut -d 'o' -f 2)
    print_msg "Current Go version is $go_version"

    go get github.com/stretchr/testify

    export CGO_ENABLED=1
    export CGO_LDFLAGS_ALLOW="-fprofile-arcs|-ftest-coverage|--coverage"
}

function install_cpp_core {
    print_msg "Installing C++ core library"
    cd $YDKGEN_HOME
    run_cmd ./generate.py -is --core --cpp
}

function install_cpp_gnmi {
    print_msg "Building C++ core gnmi library"
    cd $YDKGEN_HOME
    run_cmd ./generate.py -is --service profiles/services/gnmi-0.4.0.json --cpp
}

function install_go_core {
    print_msg "Installing Go core packages"
    cd $YDKGEN_HOME
    run_cmd ./generate.py -i --core --go
}

function install_go_gnmi {
    print_msg "Installing Go gNMI package"
    cd $YDKGEN_HOME
    run_cmd ./generate.py -i --service profiles/services/gnmi-0.4.0.json --go
}

function install_py_core {
    print_msg "Building and installing Python core package"
    cd $YDKGEN_HOME
    run_cmd ./generate.py -i --core

    print_msg "Verifying Python YDK core package installation"
    python -c "from ydk.path import NetconfSession"
    local status=$?
    if [ $status -ne 0 ]; then
        MSG_COLOR=$RED
        print_msg "Verification failed for the Python core package 'ydk_.so'"
        exit $status
    fi
}

function install_py_gnmi {
    print_msg "Installing gNMI package for Python"
    cd $YDKGEN_HOME
    run_cmd ./generate.py -i --service profiles/services/gnmi-0.4.0.json

    print_msg "Verifying Python gNMI package installation"
    if [[ $(uname) == "Linux" && ${os_info} == *"fedora"* ]]; then
        export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$YDKGEN_HOME/grpc/libs/opt:$YDKGEN_HOME/protobuf-3.5.0/src/.libs:/usr/local/lib:/usr/local/lib64:/usr/lib64
        print_msg "LD_LIBRARY_PATH is set to: $LD_LIBRARY_PATH"
    fi

    python -c "from ydk.gnmi.path import gNMISession"
    local status=$?
    if [ $status -ne 0 ]; then
        MSG_COLOR=$RED
        print_msg "Verification failed for the Python gNMI package 'ydk_gnmi_.so'"
        exit $status
    fi
}

function instal_dependencies {
    if [ ${os_type} == "Linux" ]; then
      if [[ ${os_info} == *"Ubuntu"* ]]; then
        run_cmd ${YDKGEN_HOME}/test/dependencies_ubuntu.sh
      else
        run_cmd ${YDKGEN_HOME}/test/dependencies_centos.sh
      fi
      if [ ${service_pkg} == "gnmi" ]; then
        run_cmd ${YDKGEN_HOME}/test/dependencies_linux_gnmi.sh
      fi
    else    # Darwin
      run_cmd ${YDKGEN_HOME}/test/dependencies_osx.sh
      if [ ${service_pkg} == "gnmi" ]; then
        run_cmd ${YDKGEN_HOME}/test/dependencies_osx_gnmi.sh
      fi
    fi
}

function install_ydk_cpp {
    install_cpp_core
    if [[ ${service_pkg} == "gnmi" ]]; then
        install_cpp_gnmi
    fi
}

function install_ydk_py {
    if [[ ${ydk_lang} == "py" || ${ydk_lang} == "all" ]]; then
        install_py_core
        if [[ ${service_pkg} == "gnmi" ]]; then
            install_py_gnmi
        fi
    fi
}

function install_ydk_go {
    if [[ ${ydk_lang} == "go" || ${ydk_lang} == "all" ]]; then
        init_go_env
        install_go_core
        if [[ ${service_pkg} == "gnmi" ]]; then
            install_go_gnmi
        fi
    fi
}

########################## EXECUTION STARTS HERE #############################

# Terminal colors
NOCOLOR="\033[0m"
RED="\033[0;31m"
YELLOW='\033[1;33m'
MSG_COLOR=${YELLOW}

######################################
# Parse script options

ydk_lang="py"
service_pkg="none"

# As long as there is at least one more argument, keep looping
while [[ $# -gt 0 ]]; do
    key="$1"
    case "$key" in
        # This is a flag type option. Will catch either -f or --foo
        -l|--lang)
        shift # past the key to the value
        ydk_lang="$1"
        if [[ ${ydk_lang} != "cpp" && ${ydk_lang} != "py" && ${ydk_lang} != "go" && ${ydk_lang} != "all"  ]]; then
            echo "Unknown language ${ydk_lang}"
            usage
            exit 1
        fi
        ;;
        -h|--help)
        usage
        exit 1
        ;;
        # This is an arg value type option. Will catch -o value or --output-file value
        -s|--service)
        shift # past the key and to the value
        service_pkg="$1"
        if  [[ ${service_pkg} != "gnmi" ]]; then
            echo "Unknown service package specified; gnmi assumed"
            service_pkg="gnmi"
        fi
        ;;
        *)
        # Do whatever you want with extra options
        echo "Unknown option '$key'"
        usage
        exit 1
        ;;
    esac
    # Shift after checking all the cases to get the next option
    shift
done

print_msg "YDK installation options: language=${ydk_lang}, service_package=${service_pkg}"

######################################
# Set up installation environment

os_type=$(uname)
if [[ ${os_type} == "Linux" ]]; then
    os_info=$(cat /etc/*-release)
elif [[ ${os_type} == "Darwin" ]]; then
    os_info=$(sw_vers)
else
    MSG_COLOR=${RED}
    print_msg "Unsupported OS type '${os_type}' detected"
    exit 1
fi
print_msg "Running OS type: $os_type"
print_msg "OS info: $os_info"
if [[ ${os_type} == "Linux" ]]; then
  if [[ ${os_info} == *"Ubuntu"* ]]; then
    if [[ ${os_info} != *"xenial"* && ${os_info} != *"bionic"* ]]; then
        print_msg "WARNING! Unsupported Ubuntu distribution found. Will try the best efforts."
    fi
  elif [[ ${os_info} != *"fedora"* ]]; then
    MSG_COLOR=${RED}
    print_msg "Unsupported Linux distribution detected"
    exit 1
  fi
fi

if [[ -z ${YDKGEN_HOME} || ! -d ${YDKGEN_HOME} ]]; then
    YDKGEN_HOME=${HOME}/ydk-gen
    print_msg "YDKGEN_HOME is set to ${YDKGEN_HOME}"
fi

CMAKE_BIN=cmake
which cmake3 > /dev/null
status=$?
if [[ ${status} == 0 ]]; then
    CMAKE_BIN=cmake3
fi

if [[ -z ${C_INCLUDE_PATH} ]]; then
    export C_INCLUDE_PATH=/usr/local/include
fi
if [[ -z ${CPLUS_INCLUDE_PATH} ]]; then
    export CPLUS_INCLUDE_PATH=/usr/local/include
fi

curr_dir=$(pwd)
script_dir=$(cd $(dirname ${BASH_SOURCE}) && pwd)

cd ${YDKGEN_HOME}

instal_dependencies

######################################
# Start installation

init_py_env

install_ydk-cpp

install_ydk_py

install_ydk_go

deactivate
cd ${curr_dir}
