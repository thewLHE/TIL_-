좋습니다 👍 요청 주신대로 `01_rebuild_receptors_relaxed.sh`에 대해 **스크립트 개요 → 흐름 → 이슈와 수정 과정 → 느낀 점** 순서로 TIL 정리해 드릴게요.

---

# 📓 TIL – `01_rebuild_receptors_relaxed.sh`

## 🗂 스크립트 개요

* 목적: AlphaFold 등에서 얻은 PDB 구조를 **도킹-ready receptor**로 자동 변환.
* 단계:

  1. 입력 PDB → 클린/프로톤화 (OpenBabel)
  2. (옵션) 중복 원자 제거
  3. Meeko를 이용해 receptor 파일(PDBQT/JSON/BOX) 생성
* 출력:

  * `receptor_fixed(_dedup).pdb`
  * `receptor.pdbqt` (도킹용 rigid receptor)
  * `receptor.box.txt`, `receptor.json` (박스 정의 및 메타)
* 실행 환경: `micromamba env dock`에서 OpenBabel, Meeko 필요.

---

## 📜 스크립트 흐름

1. **기본 경로 세팅**

   ```bash
   ROOT=/workspace
   RAW=$ROOT/data/raw
   WORK=$ROOT/results
   REC_OUT=$WORK/receptors
   LOG_OUT=$WORK/logs
   ```

   * 결과물은 `/workspace/results/receptors/AF-...` 아래 저장.

2. **의존성 확인**

   * `obabel` 명령어 확인.
   * `micromamba run -n dock python -c "import meeko"`로 Meeko import 체크. 실패 시 종료.

3. **박스/옵션 설정**

   * 기본 박스 중심: `(1.923, 2.619, -12.407)`
   * 기본 크기: `(22.5, 22.5, 22.5)`
   * `DO_DEDUPE=1` (중복 제거 on), `ALLOW_BAD_RES=1` (결손 잔기 허용), `KEEP_NONSTD=1` (비표준 잔기 유지), `VERBOSE=1` (Meeko verbose).

4. **유틸리티 함수**

   * `clean_pdb()`: OpenBabel로 pH 7.4 프로톤화 + 정리.
   * `dedupe_atoms_soft()`: awk로 좌표/원자명 기반 보수적 중복 제거.

5. **메인 함수 – `prepare_receptor_one()`**

   1. PDB 클린/프로톤화 → `receptor_fixed.pdb`
   2. 중복 제거 → `receptor_fixed_dedup.pdb`
   3. `mk_prepare_receptor.py` 호출, receptor 변환(PDBQT/박스/json)
   4. 산출물 검증 & 보정

      * `receptor.pdbqt` 없으면 오류
      * `receptor_vina_box.txt` → `receptor.box.txt` 동기화, 없으면 새로 생성
      * `receptor.json` 없으면 기본 메타 작성

6. **입력 수집**

   * 인자 있으면 해당 PDB만, 없으면 `RAW/AF-*.pdb` 및 `RAW/*.pdb` 전부 처리.

7. **실행 루프**

   * 각 PDB에 대해 `prepare_receptor_one` 실행
   * 실패 건수 카운트 후 요약 메시지 출력.

---

## ⚠️ 이슈와 수정 과정

1. **외부 relax 스크립트 혼동**

   * ❌ 과거 문서에서 `mk_relax_receptor.py` 호출로 오해 → 실제 스크립트는 내부 `clean_pdb`와 `dedupe_atoms_soft` 함수로 처리.
   * ✅ 수정: 문서와 설명에서 “내부 처리”임을 명확히 기록.

2. **박스 인자 분리 문제**

   * ❌ 과거에는 `"--box_center $CX $CY $CZ"`를 따옴표로 묶으면 파싱 실패.
   * ✅ 수정: **세 좌표를 개별 인자**로 전달 (`--box_center "$CX" "$CY" "$CZ"`).

3. **박스/JSON 산출물 누락**

   * ❌ Meeko가 `receptor_vina_box.txt` 같은 다른 파일명으로 저장하거나 파일이 아예 없을 때 downstream 실패.
   * ✅ 수정:

     * 존재하면 표준명(`receptor.box.txt`)으로 복사
     * 없으면 새로 생성
     * `receptor.json`도 없으면 기본값으로 생성.

4. **의존성 확인 누락**

   * ❌ 초기에는 obabel/meeko가 없을 때 바로 에러.
   * ✅ 수정: 시작부에서 **명시적으로 체크** 후 안내 메시지와 함께 종료. 진단성↑.

---

## 💡 느낀 점

* receptor 준비 파이프라인에서 **사전 클린/프로톤화**와 **중복 제거** 단계가 안정성을 크게 높여준다.
* **박스 좌표**는 반드시 타겟 pocket 중심으로 갱신해야 유효한 docking 결과를 얻을 수 있다.
* 스크립트가 누락 산출물을 자동으로 보정(`box.txt`, `json`)해 주는 부분은 재현성과 편의성을 높인다.
* “경량 의존성(OpenBabel + Meeko)” 만으로 처리되도록 구성돼 있어, 외부 Python 스크립트 유실 문제를 방지할 수 있다.

---

👉 이 TIL을 바로 `docs/TIL_01_rebuild_receptors_relaxed.md` 파일로 만들어 드릴까요?
