#!/bin/bash --login

HOST=$(hostname)
# DIR=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd -LP)
SOURCE=${BASH_SOURCE[0]}
while [ -L "$SOURCE" ]; do # resolve $SOURCE until the file is no longer a symlink
  DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
  SOURCE=$(readlink "$SOURCE")
  [[ $SOURCE != /* ]] && SOURCE=$DIR/$SOURCE # if $SOURCE was a relative symlink, we need to resolve it relative to the path where the symlink file was located
done
DIR=$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )
PARENT=$(dirname "${DIR}")

MASTER_ADDR=$(uname -n)
MASTER_PORT=20010
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
MPI_WRAPPER="${SCRIPT_DIR}/mpi_wrapper"

# SETUP_FILE="${DIR}/setup.sh"
# if [[ -f "${SETUP_FILE}" ]]; then
#   echo "source-ing ${SETUP_FILE}"
#   # shellcheck source=./setup.sh
#   source "${SETUP_FILE}"
# else
#   echo "ERROR: UNABLE TO SOURCE ${SETUP_FILE}"
# fi

ARGS_FILE="${DIR}/args.sh"
if [[ -f "${ARGS_FILE}" ]]; then
  echo "source-ing ${ARGS_FILE}"
  # shellcheck source=./args.sh
  source "${ARGS_FILE}"
else
  echo "ERROR: UNABLE TO SOURCE ${ARGS_FILE}"
fi

# MAIN="${PARENT}/pretrain_${MODEL_TYPE}.py"
MAIN=/home/czh5/seq/release/Megatron-DeepSpeed-internal/pretrain_${MODEL_TYPE}.py

printJobInfo() {
  echo "Job started at: ${TSTAMP} on $(hostname)"
  echo "Job running in: ${DIR}"
  echo "Training GPT-3 with ${MODEL_SIZE} parameters"
  echo "Writing logs to: ${OUTPUT_DIR}"
  echo 'to view output: tail -f $(tail -1 logfiles)'
  echo "i.e. tail -f $(tail -1 "${PARENT}"/logfiles)"
}

launchJob() {
  echo "using: $(which python3)" | tee -a "${OUTPUT_LOG}"
  printJobInfo | tee -a "${OUTPUT_LOG}"
  echo EXEC="${EXEC}" | tee -a "${OUTPUT_LOG}"
  echo "Writing logs to: ${OUTPUT_LOG}" | tee -a "${OUTPUT_LOG}"
  ${EXEC} "$@" # >> "${OUTPUT_LOG}" 2>&1 &
}

singleGPU() {
  echo "\
    Running on 1 host \
    with 1 GPUs each \
    for a total of 1 GPUs"
  EXEC="\
    $(which python3) \
    ${MAIN} \
    ${gpt_args} \
    ${ds_args}"
  OUTPUT_LOG="${OUTPUT_DIR}/logs/$USER-$HOST-nhosts1-ngpu1-$TSTAMP.log"
  mkdir -p "$(dirname "${OUTPUT_LOG}")"
  echo "${OUTPUT_LOG}" >> "${PARENT}/logfiles"
  printJobInfo | tee -a "${OUTPUT_LOG}"
  launchJob "$@" >> "${OUTPUT_LOG}" 2>&1 &
}

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Use all available GPUs a single nodes ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
fullNode() {

echo "fullNode started"
echo "MPI_COMMAND ${MPI_COMMAND}"
echo "MPI_DEFAULTS ${MPI_DEFAULTS}"
echo "NGPUS ${NGPUS}"
echo "hostfile ${DIR}/hostfile"
echo "MAIN ${MAIN}"
echo "gpt_args ${gpt_args}"

  NHOSTS=$(wc -l < "${HOSTFILE}")
  NGPU_PER_HOST=$(nvidia-smi -L | wc -l)
  # NGPU_PER_HOST=1
  NGPUS=$((${NHOSTS}*${NGPU_PER_HOST}))
  # hostname > $DIR/hostfile
  echo "\
    Running on $NHOSTS hosts \
    with $NGPU_PER_HOST GPUs each \
    for a total of $NGPUS GPUs"
  EXEC="\
    ${MPI_COMMAND} \
    ${MPI_DEFAULTS} \
    "${MPI_ELASTIC}"
    ${MPI_WRAPPER} ${MASTER_ADDR} ${MASTER_PORT} \
    ${MAIN} \
    ${gpt_args} \
    ${ds_args}"
  OUTPUT_LOG="${OUTPUT_DIR}/logs/$USER-$HOST-nhosts${NHOSTS}-ngpu${NGPUS}-$TSTAMP.log"
  mkdir -p "$(dirname "${OUTPUT_LOG}")"
  echo "${OUTPUT_LOG}" >> "${PARENT}/logfiles"
  printJobInfo | tee -a "${OUTPUT_LOG}"
  launchJob "$@" 2>&1 | tee "${OUTPUT_LOG}"
}

# ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
# ┃ Use all available GPUs on all available nodes ┃
# ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
elasticDistributed() {
  NHOSTS=$(wc -l < "${HOSTFILE}")
  NGPU_PER_HOST=$(nvidia-smi -L | wc -l)
  NGPUS=$((${NHOSTS}*${NGPU_PER_HOST}))
  echo "\
    Running on ${NHOSTS} hosts \
    with ${NGPU_PER_HOST} GPUs each \
    for a total of ${NGPUS} GPUs"
  EXEC_STR=(
    "${MPI_COMMAND}"
    "${MPI_DEFAULTS}"
    "${MPI_ELASTIC}"
    "$(which python3)"
    "${MAIN}"
    "${gpt_args}"
    "${ds_args}"
  )
  EXEC="${EXEC_STR[*]}"
  OUTPUT_LOG="${OUTPUT_DIR}/logs/$USER-$HOST-nhosts${NHOSTS}-ngpu${NGPUS}-$TSTAMP.log"
  mkdir -p "$(dirname "${OUTPUT_LOG}")"
  echo "${OUTPUT_LOG}" >> "${PARENT}/logfiles"
  printJobInfo | tee -a "${OUTPUT_LOG}"
#   launchJob "$@" >> "${OUTPUT_LOG}" 2>&1 &
  launchJob "$@"
}
