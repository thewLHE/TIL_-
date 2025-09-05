# /workspace/scripts/000_chemprot_restore_bundle/01_rebuild_receptors_relaxed.sh
#!/usr/bin/env bash
# Rebuild receptors (relaxed): RAW PDB -> cleaned/protonated PDB -> receptor.pdbqt (+box/json)
# - box 인자는 반드시 3개씩 개별 인자로 전달 (--box_center "$CX" "$CY" "$CZ")
# - micromamba env: dock
set -Eeuo pipefail

# ================== 0) 기본 경로/출력 ==================
ROOT=${ROOT:-/workspace}
RAW=${RAW:-"$ROOT/data/raw"}              # 입력 PDB 폴더 (AF-*.pdb 등)
WORK=${WORK:-"$ROOT/results"}             # 결과 루트
REC_OUT="$WORK/receptors"
LOG_OUT="$WORK/logs"
mkdir -p "$REC_OUT" "$LOG_OUT"

# ================== 1) 도구 확인 ==================
need() { command -v "$1" >/dev/null 2>&1 || { echo "[ERR] '$1' not found"; exit 1; }; }

OBABEL_BIN=${OBABEL_BIN:-$(command -v obabel || true)}
need obabel
if ! micromamba run -n dock python -c "import meeko" >/dev/null 2>&1; then
  echo "[ERR] 'meeko'가 env 'dock'에서 import되지 않습니다."; exit 1
fi

# ================== 2) 박스/옵션 ==================
: "${CX:=1.923}" ; : "${CY:=2.619}" ; : "${CZ:=-12.407}"
: "${SX:=22.5}"  ; : "${SY:=22.5}"  ; : "${SZ:=22.5}"

DO_DEDUPE=${DO_DEDUPE:-1}           # 1: 중복원자 보수적 제거
ALLOW_BAD_RES=${ALLOW_BAD_RES:-1}   # 1: 결손 잔기 허용(삭제)
KEEP_NONSTD=${KEEP_NONSTD:-1}       # 1: 비표준/ligand 잔기 유지
VERBOSE=${VERBOSE:-1}               # 1: meeko -v

echo "[INFO] RAW=$RAW"
echo "[INFO] OUT=$REC_OUT"
echo "[INFO] BOX center=($CX $CY $CZ) size=($SX $SY $SZ)"

# ================== 3) 유틸리티 ==================
clean_pdb() {
  local in_pdb="$1" out_pdb="$2" log="$3"
  # pH 7.4 근사 양성자화, kekulize 경고는 로그에만 남김
  "$OBABEL_BIN" -ipdb "$in_pdb" -opdb -O "$out_pdb" --addh --pH 7.4 |& tee -a "$log" || true
}

dedupe_atoms_soft() {
  local in_pdb="$1" out_pdb="$2"
  # 같은 좌표/원자명 중복을 보수적으로 제거(안전 모드)
  awk '
    /^ATOM|^HETATM/ { key=$1" "$3" "$6" "$7" "$8; if (!seen[key]++) print; next }
    { print }
  ' "$in_pdb" > "$out_pdb"
}

prepare_receptor_one() {
  local pdb="$1"
  local base; base="$(basename "$pdb")"; base="${base%.*}"
  local outdir="$REC_OUT/$base"
  local log="$LOG_OUT/${base}_prepare_receptor.log"
  mkdir -p "$outdir"

  echo
  echo "[INFO] === $base ==="
  echo "[INFO] in=$pdb"
  echo "[INFO] outdir=$outdir log=$log"

  # 1) 클린/프로톤화
  local fixed="$outdir/receptor_fixed.pdb"
  clean_pdb "$pdb" "$fixed" "$log"

  # 2) (옵션) 보수적 dedupe
  if [[ "$DO_DEDUPE" == "1" ]]; then
    local fixed2="$outdir/receptor_fixed_dedup.pdb"
    dedupe_atoms_soft "$fixed" "$fixed2"
    fixed="$fixed2"
  fi

  # 3) meeko receptor 작성 (네가 성공시킨 단일 커맨드와 동일한 옵션)
  meeko_args=( -i "$fixed" -o "$outdir/receptor" -p -j )
  [[ "$VERBOSE" == "1"       ]] && meeko_args+=( -v )
  [[ "$ALLOW_BAD_RES" == "1" ]] && meeko_args+=( --allow_bad_res )

  # 박스 인자
  meeko_args+=( --box_center "$CX" "$CY" "$CZ" )
  meeko_args+=( --box_size   "$SX" "$SY" "$SZ" )

  {
    echo "[CMD] mk_prepare_receptor.py ${meeko_args[*]}"
    micromamba run -n dock mk_prepare_receptor.py "${meeko_args[@]}"
  } |& tee -a "$log"

  # 4) 산출물 확인/보정
  if [[ ! -f "$outdir/receptor.pdbqt" ]]; then
    echo "[ERR] receptor.pdbqt 생성 실패 ($base). 로그 확인: $log"
    return 1
  fi

  # Vina 박스 파일명 동기화
  if [[ -f "$outdir/receptor_vina_box.txt" ]]; then
    cp -f "$outdir/receptor_vina_box.txt" "$outdir/receptor.box.txt"
  elif [[ ! -f "$outdir/receptor.box.txt" ]]; then
    # 혹시라도 박스 파일이 안 생기면 기본 포맷으로 생성
    cat > "$outdir/receptor.box.txt" <<EOF
center_x = $CX
center_y = $CY
center_z = $CZ
size_x   = $SX
size_y   = $SY
size_z   = $SZ
EOF
  fi

  # json 메타(있으면 유지, 없으면 생성)
  if [[ ! -f "$outdir/receptor.json" ]]; then
    cat > "$outdir/receptor.json" <<JSON
{"center":[${CX},${CY},${CZ}],"size":[${SX},${SY},${SZ}]}
JSON
  fi

  ls -lh "$outdir"/receptor.pdbqt "$outdir"/receptor*.txt "$outdir"/receptor*.json 2>/dev/null || true
  echo "✔ done: $base"
}

# ================== 4) 입력 수집 ==================
# 인자로 파일을 주면 그 파일들만, 아니면 RAW/*.pdb
if (( "$#" > 0 )); then
  PDBS=("$@")
else
  shopt -s nullglob
  PDBS=("$RAW"/AF-*.pdb "$RAW"/*.pdb)
fi

if (( ${#PDBS[@]} == 0 )); then
  echo "[ERR] 대상 PDB가 없습니다. (RAW=$RAW, args=none)"; exit 1
fi

# ================== 5) 실행 ==================
fail=0
for pdb in "${PDBS[@]}"; do
  prepare_receptor_one "$pdb" || fail=$((fail+1))
done

echo
if (( fail > 0 )); then
  echo "[WARN] 완료했지만 실패 $fail 건 있음. 로그: $LOG_OUT"
  exit 1
else
  echo "🎉 All receptors rebuilt successfully."
fi
