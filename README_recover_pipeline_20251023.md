
---

# 📘 SKAI / Docker Data Recovery & Environment Analysis — Technical README

**작성일:** 2025-10-23
**작성자:** LHE
**문서 목적:**
Docker Desktop for WSL2 환경의 손상된 ext4.vhdx를 직접 마운트·복구하여
컨테이너 환경(패키지 버전, 경로 구조, 실행 이력 등)을 분석하고,
재구성 가능성을 검증한 전체 실험 로그 + 코드 + 데이터 계보 통합 백서.

---

## 🧭 0. 배경 및 문제 발생 원인 (Root Cause Exploration)

### 📍 상황 개요

* 연구 환경: Windows + WSL2 (Ubuntu-20.04) + Docker Desktop
* Docker Desktop 데이터 저장 위치:
  `C:\Users\<USER>\AppData\Local\DockerDesktopWSL\data\ext4.vhdx`
* 백업본 존재 경로:

  ```
  X:\LHE\DockerDesktopWSL\disk\docker_data.vhdx
  D:\LHE\DockerDesktopWSL\disk\ext4.vhdx
  ```

### ⚠️ 발생한 문제

* Docker Desktop 실행 불가,
  `Wsl/Service/RegisterDistro/WSL_E_DISK_CORRUPTED` 에러 발생.
* `ext4.vhdx`의 내부 파일 시스템은 살아있으나, Docker Desktop 서비스가 mount 실패.
* 즉, Docker의 `/var/lib/docker` 계층 자체는 존재하나 접근 불가 상태.

### 🔎 Root Cause 추정

| 구분 | 원인 가능성                             | 근거                                                     |
| -- | ---------------------------------- | ------------------------------------------------------ |
| 1  | Docker Desktop 종료 중 강제 종료          | WSL instance `docker-desktop-data`가 clean unmount되지 않음 |
| 2  | `ext4.vhdx` 오버사이즈 및 NTFS 캐시 오류     | 약 200 GB 이상, NTFS + WSL 사이 I/O hang 기록                 |
| 3  | Windows Defender / VSS snapshot 충돌 | WSL 디스크를 인식 중 백업 툴이 snapshot 동결                        |
| 4  | Docker update 중 metadata 손상        | image/overlay2/layerdb 내 일부 json invalid 발생 가능         |

→ 결론적으로, **VHDX 파일 시스템은 손상되지 않았으나,
Docker Desktop의 메타레이어(index.json, layerdb) 일부가 깨져 Docker daemon 부팅 불가 상태**.

---

## ⚙️ 1. 실험 및 복구 절차 (전체 실행 로그)

### 1-1. 대상 디스크 탐색

```powershell
ls D:\LHE\DockerDesktopWSL\disk
ls X:\LHE\DockerDesktopWSL\disk
```

결과:

```
D:\LHE\DockerDesktopWSL\disk\
 ├─ docker_data.vhdx (208 GB)
 └─ ext4.vhdx        (208 GB)
X:\LHE\DockerDesktopWSL\disk\
 └─ docker_data.vhdx (213 GB)
```

---

### 1-2. PowerShell에서 VHDX 읽기 및 WSL import

```powershell
$VHDX  = "D:\LHE\DockerDesktopWSL\disk\ext4.vhdx"
$Store = "C:\wsl_recover\data"
$Distro = "docker-data-recover"

wsl --shutdown
wsl --unregister $Distro 2>$null
wsl --import $Distro $Store $VHDX --version 2
```

→ 실패: `WSL_E_DISK_CORRUPTED`

---

### 1-3. Mount-VHD 직접 연결

```powershell
Mount-VHD -Path $VHDX -ReadOnly -NoDriveLetter -PassThru
Get-Disk
Get-Partition -DiskNumber <N>
```

→ 파티션 인식 실패.
그래서 WSL native mount 시도.

---

### 1-4. WSL native mount 성공

```powershell
$VHDX = "X:\LHE\DockerDesktopWSL\disk\docker_data.vhdx"
$NAME = "dd-recover"
wsl --mount --vhd "$VHDX" --type ext4 --name $NAME
```

✅ `/mnt/wsl/dd-recover/`로 마운트 성공.

---

### 1-5. /var/lib/docker 백업 (WSL 내부 tar)

```bash
sudo tar -C /mnt/wsl/dd-recover -czf /mnt/d/LHE/DockerRecover/docker_data_from_vhdx_20251022_111548.tgz data/docker
```

✅ 약 43 GB `docker_data_from_vhdx_20251022_111548.tgz` 생성.

---

## 🧮 2. 데이터 분석 파이프라인

### 2-1. 압축 해제

> NTFS에서는 `mknod` 지원 안 하므로, 반드시 EXT4(Home) 내에서 수행.

```bash
mkdir ~/extracted_on_wsl
sudo tar -xzf /mnt/d/LHE/DockerRecover/docker_data_from_vhdx_20251022_111548.tgz -C ~/extracted_on_wsl
```

구조:

```
~/extracted_on_wsl/data/docker/
 ├─ containers/
 ├─ image/overlay2/imagedb/content/sha256/
 ├─ image/overlay2/layerdb/sha256/
 ├─ overlay2/<cache-id>/diff/
 └─ repositories.json
```

---

### 2-2. APT 패키지 버전 추출

```bash
pwsh -NoProfile -File /mnt/d/LHE/DockerRecover/Analyze-DockerData_fromDir.ps1 -ExtractDir "~/extracted_on_wsl"
```

출력:

```
==> CSV: /home/lhe/extracted_on_wsl/apt_packages_by_image.csv
```

결과 요약:

| package | micapipe        | qsiprep      | fmriprep          |
| ------- | --------------- | ------------ | ----------------- |
| adduser | 3.116ubuntu1    | 3.116ubuntu1 | 3.113+nmu3ubuntu4 |
| apt     | 1.6.12ubuntu0.1 | 1.6.17       | 1.2.32            |

---

### 2-3. pip / conda 패키지 버전 추출 (v2)

기존 `Analyze-PythonConda_fromDir.ps1`는 `layerdb 없음` 오류 → 수정판 제작.

**핵심 보완점**

* layerdb A/B 자동 탐지
  (`overlay2/layerdb` vs `image/overlay2/layerdb`)
* root 권한 접근 및 JSON 로딩 보정
* 결과 CSV 두 개로 분리 저장

```bash
sudo pwsh -NoProfile -File /mnt/d/LHE/DockerRecover/Analyze-PythonConda_fromDir_v2.ps1 -ExtractDir "/home/lhe/extracted_on_wsl"
```

출력:

```
==> Wrote:
   pip_packages_by_image.csv
   conda_packages_by_image.csv
```

---

### 2-4. APT 버전 매트릭스 생성

```bash
pwsh -NoProfile -File /mnt/d/LHE/DockerRecover/Summarize-AptPackages.ps1 -CsvPath "/home/lhe/extracted_on_wsl/apt_packages_by_image.csv"
```

출력:

```
common_packages.csv
per_image_unique_packages.csv
apt_matrix.csv
```

---

## 📊 3. 주요 입출력 명세

| 구분     | 파일/경로                                                                | 설명                  |
| ------ | -------------------------------------------------------------------- | ------------------- |
| **입력** | `D:\LHE\DockerDesktopWSL\disk\ext4.vhdx`                             | 손상된 Docker 데이터 VHDX |
| 〃      | `/mnt/wsl/dd-recover/data/docker`                                    | 복구된 Docker 내부 구조    |
| **출력** | `/mnt/d/LHE/DockerRecover/docker_data_from_vhdx_20251022_111548.tgz` | 전체 tar 백업           |
| 〃      | `/home/lhe/extracted_on_wsl/apt_packages_by_image.csv`               | OS 패키지              |
| 〃      | `/home/lhe/extracted_on_wsl/pip_packages_by_image.csv`               | Python 패키지          |
| 〃      | `/home/lhe/extracted_on_wsl/conda_packages_by_image.csv`             | Conda 패키지           |
| 〃      | `/home/lhe/extracted_on_wsl/apt_matrix.csv`                          | 버전 교차 매트릭스          |
| 〃      | `/home/lhe/extracted_on_wsl/common_packages.csv`                     | 공통 패키지 교집합          |
| 〃      | `/home/lhe/extracted_on_wsl/per_image_unique_packages.csv`           | 이미지별 고유 패키지         |

---

## 🧠 4. 분석 인사이트

| 범주         | 관찰 결과                                                      | 해석                                     |
| ---------- | ---------------------------------------------------------- | -------------------------------------- |
| APT 버전 편차  | Ubuntu 16~18~20 계열 혼재                                      | 이미지별 base image 세대 차이                  |
| pip 패키지    | scipy / numpy / nibabel / nipype 공통                        | neuroimaging pipeline 공통 기반            |
| conda 패키지  | miniconda 기반 micapipe / qsiprep, system-python 기반 fmriprep | Python/conda 혼합 운영                     |
| 공통 3-stack | apt + pip + conda 공통 dependency 존재                         | 완전한 isolate 불가, cross-dependency 관리 필요 |

---

## 🔧 5. 재현 코드 및 경로 구조 요약

```bash
# 백업
sudo tar -C /mnt/wsl/dd-recover -czf /mnt/d/LHE/DockerRecover/docker_data_from_vhdx_<TS>.tgz data/docker

# 압축 해제
sudo tar -xzf /mnt/d/LHE/DockerRecover/docker_data_from_vhdx_<TS>.tgz -C ~/extracted_on_wsl

# 분석 단계별
pwsh -File Analyze-DockerData_fromDir.ps1      -ExtractDir "~/extracted_on_wsl"
pwsh -File Summarize-AptPackages.ps1           -CsvPath    "~/extracted_on_wsl/apt_packages_by_image.csv"
pwsh -File Analyze-PythonConda_fromDir_v2.ps1  -ExtractDir "~/extracted_on_wsl"

# 결과 복제
cp -a ~/extracted_on_wsl /mnt/d/LHE/DockerRecover/extracted_on_wsl_<TS>/
```

---

## 🧩 6. 파이프라인 전체 다이어그램

```mermaid
flowchart TD
  A[VHDX Mount (wsl --mount)] --> B[tar backup: data/docker]
  B --> C[Extract to ~/extracted_on_wsl]
  C --> D1[APT analysis (Analyze-DockerData_fromDir.ps1)]
  C --> D2[Pip/Conda analysis (Analyze-PythonConda_fromDir_v2.ps1)]
  D1 --> E[Summarize-AptPackages.ps1]
  D2 --> E
  E --> F[Output CSVs + matrix]
  F --> G[Standardization / Rebuild Plan]
```

---

## 🔬 7. 근본 원인에 대한 실험적 검증

* VHDX integrity 검사 (`fsck.ext4`) → 정상
* 내부 `/var/lib/docker` 계층 구조 → 완전
* 그러나 `docker image ls` 불가 → `metadata.db` (Boltdb) 손상 가능성
* 즉, **Docker metadata (daemon DB)** 와 **image filesystem(layer)** 는 분리되어 있고
  layer 자체는 살아있음 → `image/overlay2/imagedb`로 복구 가능.

---

## 📘 8. 결론

| 항목                   | 결과                                    |
| -------------------- | ------------------------------------- |
| Docker Desktop 손상 원인 | metadata DB 손상 (WSL unclean shutdown) |
| 데이터 보존 여부            | layer 데이터 100% 복원 가능                  |
| 분석 산출물               | apt / pip / conda 3-level 패키지 매트릭스 확보 |
| 향후 계획                | 표준 버전 세트 구축 + 재구성용 Dockerfile 생성      |

---

## 📎 부록: 디렉터리 트리 요약

```
D:\LHE\DockerRecover\
 ├─ docker_data_from_vhdx_20251022_111548.tgz
 ├─ Analyze-DockerData_fromDir.ps1
 ├─ Analyze-PythonConda_fromDir_v2.ps1
 ├─ Summarize-AptPackages.ps1
 ├─ extracted_on_wsl/
 │   ├─ data/docker/
 │   ├─ apt_packages_by_image.csv
 │   ├─ pip_packages_by_image.csv
 │   ├─ conda_packages_by_image.csv
 │   ├─ apt_matrix.csv
 │   └─ common_packages.csv
 └─ note_analy_dockerdata.md
```

---

## 🧩 부록 B: 주요 명령 및 이유

| 명령                                  | 목적                                |
| ----------------------------------- | --------------------------------- |
| `wsl --mount --vhd ...`             | VHDX를 직접 ext4로 마운트                |
| `tar -czf`                          | `/var/lib/docker` 구조 백업           |
| `tar -xzf`                          | NTFS 대신 EXT4 홈에 압축 해제             |
| `pwsh -File Analyze-...`            | PowerShell 기반 분석 (cross-platform) |
| `chmod -R a+rX`                     | root-owned 파일 접근 허용               |
| `snap install powershell --classic` | WSL용 pwsh 설치                      |

---

## 📍 Insight Summary

* **Docker Desktop의 VHDX는 단일 실패점(single-point-of-failure)** → 주기적 스냅샷 필요
* **WSL ext4.vhdx는 mount로 직접 접근 가능** → 복구 루트로 유용
* **APT/pip/conda 통합 매트릭스**는 컨테이너 환경 통합 검증에 결정적
* **PowerShell Core + WSL** 조합으로 cross-OS 로그 및 CSV 추출 자동화 가능
* **향후 자동 리포트화**(“Recover → Extract → Analyze → Report”) 가능

---
