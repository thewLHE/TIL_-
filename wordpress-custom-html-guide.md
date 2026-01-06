# WordPress Custom HTML 블록 작성 가이드라인

> **GeneOn BioTech 웹사이트 (Bridge 테마 + WPBakery)**
> 
> 작성일: 2026-01-06

---

## 핵심 원칙

**"전역을 이기려 하지 말고, 섹션을 고립(격리)시킨다"**

WordPress 테마(특히 Bridge)는 매우 공격적인 CSS 특이성을 가지고 있어서, 
일반적인 CSS 클래스로는 스타일이 덮어씌워집니다.

---

## ✅ 작동하는 방식

### 순수 HTML + 인라인 스타일 (권장)

```html
<!-- 1. 최소한의 스코프 CSS -->
<style>
#my-page * { box-sizing: border-box !important; }
#my-page { font-family: 'Pretendard', sans-serif; line-height: 1.6; }
</style>

<!-- 2. 래퍼 ID로 격리 -->
<div id="my-page" style="background-color: #05080f; width: 100%; margin: 0; padding: 0;">
    
    <!-- 3. 모든 스타일은 인라인으로 -->
    <section style="padding: 80px 20px; background: #05080f;">
        <div style="max-width: 1200px; margin: 0 auto;">
            <h1 style="font-size: 3rem; color: #fff; font-weight: 800;">
                제목
            </h1>
        </div>
    </section>
    
</div>
```

### 작동 예시 참고
- CES 2026 페이지
- Contact - Investors 페이지

---

## ❌ 피해야 하는 방식

### 1. JavaScript로 HTML 동적 삽입

```javascript
// ❌ WordPress가 < 문자를 HTML로 파싱하여 JS 오류 발생
shadow.innerHTML = '<div>...</div>';

// ❌ 이스케이프해도 WordPress 환경에서 불안정
shadow.innerHTML = '\x3Cdiv\x3E...\x3C/div\x3E';
```

**오류 메시지:**
```
Uncaught SyntaxError: Unexpected token '<'
```

### 2. Shadow DOM

```javascript
// ❌ WordPress Custom HTML 블록에서 불안정
var shadow = root.attachShadow({mode: 'open'});
```

### 3. 템플릿 리터럴 (백틱)

```javascript
// ❌ WordPress가 스마트 따옴표로 변환
const html = `<div>...</div>`;
```

### 4. 외부 CSS 파일 의존

```html
<!-- ❌ 테마 CSS에 의해 덮어씌워짐 -->
<link rel="stylesheet" href="my-styles.css">
```

---

## 코드 작성 규칙

### 1. 문서 태그 제거

```html
<!-- ❌ 잘못된 예 -->
<!DOCTYPE html>
<html>
<head>...</head>
<body>
    ...
</body>
</html>

<!-- ✅ 올바른 예 -->
<style>...</style>
<div id="my-page">
    ...
</div>
```

### 2. 고유 ID로 래퍼 격리

```html
<!-- 페이지별 고유 ID 사용 -->
<div id="geneon-ir-page">...</div>
<div id="geneon-ces-page">...</div>
<div id="geneon-pipeline-page">...</div>
```

### 3. 인라인 스타일 우선

테마가 덮어써도 절대 안 깨져야 하는 요소:
- 배경색
- 텍스트 색상
- 레이아웃 (width, max-width, margin, padding)
- 그리드/플렉스 구조

```html
<!-- ✅ 인라인 스타일 = 최고 우선순위 -->
<div style="background: #05080f; color: #fff; padding: 80px 20px;">
```

### 4. Flexbox 중심 레이아웃

Grid는 테마 충돌 가능성이 높으므로 Flexbox 권장:

```html
<!-- ✅ Flexbox - 중앙 정렬 안정적 -->
<div style="display: flex; flex-wrap: wrap; gap: 30px; justify-content: center;">
    <div style="flex: 1 1 300px; max-width: 380px;">카드 1</div>
    <div style="flex: 1 1 300px; max-width: 380px;">카드 2</div>
    <div style="flex: 1 1 300px; max-width: 380px;">카드 3</div>
</div>
```

### 5. 컨테이너 중앙 정렬

```html
<div style="max-width: 1200px; margin: 0 auto; padding: 0 20px;">
    <!-- 콘텐츠 -->
</div>
```

### 6. WordPress 자동 태그 주입 방지

WordPress는 빈 줄을 `<p>` 또는 `<br>`로 변환합니다.

```html
<!-- ❌ 빈 줄이 있으면 -->
<div>

    <span>텍스트</span>

</div>

<!-- WordPress가 이렇게 변환 -->
<div>
<p></p>
    <span>텍스트</span>
<p></p>
</div>

<!-- ✅ 빈 줄 최소화 -->
<div><span>텍스트</span></div>
```

---

## 스타일 가이드 (GeneOn 다크 테마)

### 색상 팔레트

| 용도 | 색상 코드 |
|------|----------|
| 배경 (메인) | `#05080f` |
| 배경 (섹션) | `#080c16` |
| 배경 (카드) | `rgba(255,255,255,0.02)` |
| 테두리 | `rgba(255,255,255,0.1)` |
| 텍스트 (제목) | `#ffffff` |
| 텍스트 (본문) | `#a0aabf` |
| 텍스트 (보조) | `#64748b` |
| 액센트 (그린) | `#00ff9d` |
| 액센트 (블루) | `#00d4ff` |

### 타이포그래피

```html
<!-- 폰트 임포트 -->
<style>
@import url('https://cdn.jsdelivr.net/gh/orioncactus/pretendard/dist/web/static/pretendard.css');
#my-page { font-family: 'Pretendard', -apple-system, sans-serif; }
</style>

<!-- 제목 -->
<h1 style="font-size: 3.5rem; font-weight: 800; line-height: 1.2;">

<!-- 소제목 -->
<h2 style="font-size: 2.2rem; font-weight: 700;">

<!-- 본문 -->
<p style="font-size: 1rem; line-height: 1.6;">
```

### 그라디언트 배경 (Hero 섹션)

```html
<section style="background: radial-gradient(circle at 50% 30%, #1a233a 0%, #05080f 80%);">
```

### 카드 스타일

```html
<div style="
    background: rgba(255,255,255,0.02);
    border: 1px solid rgba(255,255,255,0.1);
    border-radius: 16px;
    padding: 40px;
">
```

### 버튼 스타일

```html
<a href="#" style="
    display: inline-block;
    padding: 16px 40px;
    background: linear-gradient(90deg, #00ff9d 0%, #00d4ff 100%);
    color: #000;
    font-weight: 700;
    text-decoration: none;
    border-radius: 8px;
    text-align: center;
">
    버튼 텍스트
</a>
```

---

## 반응형 처리

인라인 스타일에서는 미디어 쿼리 사용이 제한적이므로, 
Flexbox의 `flex-wrap: wrap`과 `flex: 1 1 {min-width}`로 처리:

```html
<!-- 3열 → 2열 → 1열 자동 변환 -->
<div style="display: flex; flex-wrap: wrap; gap: 30px; justify-content: center;">
    <div style="flex: 1 1 300px; max-width: 380px;">...</div>
    <div style="flex: 1 1 300px; max-width: 380px;">...</div>
    <div style="flex: 1 1 300px; max-width: 380px;">...</div>
</div>
```

필요시 `<style>` 태그 내에 미디어 쿼리 추가:

```html
<style>
@media (max-width: 768px) {
    #my-page h1 { font-size: 2.5rem !important; }
    #my-page .hero-section { padding: 60px 15px !important; }
}
</style>
```

---

## SVG 아이콘 사용

외부 아이콘 라이브러리 대신 인라인 SVG 권장:

```html
<svg viewBox="0 0 24 24" width="24" height="24" stroke="#00ff9d" fill="none" stroke-width="2">
    <circle cx="12" cy="12" r="10"></circle>
</svg>
```

---

## 체크리스트

코드 제출 전 확인사항:

- [ ] `<!DOCTYPE>`, `<html>`, `<head>`, `<body>` 태그 제거됨
- [ ] 고유 ID로 래퍼 격리됨 (`#geneon-xxx-page`)
- [ ] 핵심 스타일은 모두 인라인으로 적용됨
- [ ] JavaScript 사용 없음 (또는 최소화)
- [ ] Grid 대신 Flexbox 사용
- [ ] 불필요한 빈 줄 제거됨
- [ ] 로컬 브라우저에서 미리보기 테스트 완료

---

## 트러블슈팅

### 문제: 콘텐츠가 왼쪽으로 몰림

**해결:**
```html
<div style="max-width: 1200px; margin: 0 auto; padding: 0 20px;">
```

### 문제: 테마 CSS가 색상을 덮어씀

**해결:**
```html
<h1 style="color: #fff !important;">
```

### 문제: 카드가 한 줄에 안 맞음

**해결:**
```html
<div style="display: flex; flex-wrap: wrap; gap: 30px; justify-content: center;">
    <div style="flex: 1 1 300px; max-width: 380px;">
```

### 문제: 모바일에서 깨짐

**해결:**
```html
<style>
@media (max-width: 768px) {
    #my-page .section { padding: 60px 15px !important; }
}
</style>
```

---

## 참고 자료

- 작동 예시: CES 페이지 (`geneon-ces-page`)
- 작동 예시: IR 페이지 (`geneon-ir-page`)
- WPBakery 숏코드 방식: Main Page (전임자 작성)

---

*Last Updated: 2026-01-06*
