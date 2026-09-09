# 2주차 활동지 / Week 2 Worksheet

**AI 협업 방식 비교 / Comparing two ways of working with AI**

- 작성일 / Date: 2026년 9월 9일
- 참여자 / Present: 강동혁, 강재환, 박제헌, 오형석
- 결과보고서 / Report chapter: 6장 AI 활용과 판단
- 최종 반영 / Feeds into: PROMPTS.md 첫 항목

---

## 구현할 작은 기능 / Small feature

> 메모 검색 기능을 추가하라. 제목과 본문에서 키워드로 찾을 수 있어야 한다.


## 사용한 도구 / Tool used

Claude Haiku 4.5


## 방식 A — 통째로 요청 / One big request

프롬프트
```
메모 검색 기능 만들어줘. 제목이랑 본문에서 키워드로 찾을 수 있게.
```
결과
```
메모 검색 기능이 있는 앱을 만들어드리겠습니다. 제목과 본문에서 키워드로 검색할 수 있습니다.

이제 메모 검색 앱을 만들겠습니다.

메모

제목이나 본문에서 검색... (+ 추가)

메모 검색 앱을 만들었습니다!

주요 기능:

실시간 검색 — 검색창에 입력하면 제목과 본문 모두에서 키워드를 찾습니다
메모 추가 — "+ 추가" 버튼으로 새로운 메모를 작성할 수 있습니다
메모 삭제 — 각 메모의 휴지통 아이콘으로 삭제 가능합니다
결과 개수 표시 — 검색 결과의 개수를 보여줍니다
샘플 메모 4개가 이미 등록되어 있으니 검색해보세요. 예를 들어 "프로젝트", "코드", "팀" 등으로 검색하면 관련 메모들이 필터링됩니다.
```

```
<div style="padding: 1.5rem 0;">
  <div style="margin-bottom: 2rem;">
    <h2 style="font-size: 18px; font-weight: 500; margin: 0 0 1rem 0; color: var(--text-primary);">메모</h2>
    
    <div style="display: flex; gap: 8px; margin-bottom: 1.5rem;">
      <input 
        type="text" 
        id="searchInput" 
        placeholder="제목이나 본문에서 검색..."
        style="flex: 1; padding: 10px 12px; border: 0.5px solid var(--border); border-radius: var(--radius); font-size: 14px; background: var(--surface-2);"
      />
      <button 
        onclick="addMemo()"
        style="padding: 10px 16px; background: var(--fill-accent); color: var(--on-accent); border: none; border-radius: var(--radius); font-size: 14px; font-weight: 500; cursor: pointer;"
      >
        + 추가
      </button>
    </div>

    <div style="display: flex; gap: 8px; margin-bottom: 1.5rem; flex-wrap: wrap;">
      <span style="font-size: 13px; color: var(--text-secondary);">전체</span>
      <span id="resultCount" style="font-size: 13px; color: var(--text-secondary); font-weight: 500;"></span>
    </div>
  </div>

  <div id="memoList" style="display: flex; flex-direction: column; gap: 12px;"></div>

  <!-- 숨겨진 추가 폼 -->
  <div id="addForm" style="display: none; background: var(--surface-1); border: 0.5px solid var(--border); border-radius: 12px; padding: 1.25rem; margin-top: 1.5rem;">
    <h3 style="font-size: 16px; font-weight: 500; margin: 0 0 1rem 0; color: var(--text-primary);">새 메모</h3>
    <input 
      type="text" 
      id="newTitle" 
      placeholder="제목"
      style="width: 100%; padding: 10px 12px; border: 0.5px solid var(--border); border-radius: var(--radius); font-size: 14px; margin-bottom: 10px; box-sizing: border-box;"
    />
    <textarea 
      id="newContent" 
      placeholder="본문"
      style="width: 100%; padding: 10px 12px; border: 0.5px solid var(--border); border-radius: var(--radius); font-size: 14px; margin-bottom: 10px; resize: vertical; min-height: 80px; box-sizing: border-box;"
    ></textarea>
    <div style="display: flex; gap: 8px;">
      <button 
        onclick="saveMemo()"
        style="flex: 1; padding: 10px 12px; background: var(--fill-accent); color: var(--on-accent); border: none; border-radius: var(--radius); font-size: 14px; font-weight: 500; cursor: pointer;"
      >
        저장
      </button>
      <button 
        onclick="cancelAdd()"
        style="flex: 1; padding: 10px 12px; background: var(--surface-2); color: var(--text-primary); border: 0.5px solid var(--border); border-radius: var(--radius); font-size: 14px; font-weight: 500; cursor: pointer;"
      >
        취소
      </button>
    </div>
  </div>
</div>

<script>
let memos = [
  { id: 1, title: '프로젝트 계획', content: '새로운 모바일 앱 프로젝트 시작. UI/UX 디자인부터 진행. 팀미팅은 월요일 10시.' },
  { id: 2, title: '코드 리뷰 체크리스트', content: '함수 이름 명확성 확인\n변수 네이밍 규칙 준수\n에러 핸들링 처리\n주석 작성 여부' },
  { id: 3, title: '회의 메모', content: '분기별 목표 설정\n팀 구성원 역할 배분\n예산 검토 및 승인' },
  { id: 4, title: '학습 목표', content: 'React 고급 패턴 학습\nTypeScript 타입 시스템 깊이 있게 이해\n성능 최적화 기법 습득' }
];

let nextId = 5;
const searchInput = document.getElementById('searchInput');
const memoList = document.getElementById('memoList');
const resultCount = document.getElementById('resultCount');
const addForm = document.getElementById('addForm');

searchInput.addEventListener('input', (e) => {
  const query = e.target.value.toLowerCase().trim();
  filterAndDisplay(query);
});

function filterAndDisplay(query) {
  const filtered = query === '' 
    ? memos 
    : memos.filter(memo => 
        memo.title.toLowerCase().includes(query) || 
        memo.content.toLowerCase().includes(query)
      );

  resultCount.textContent = `${filtered.length}개`;
  
  memoList.innerHTML = filtered.map(memo => `
    <div style="background: var(--surface-1); border: 0.5px solid var(--border); border-radius: 12px; padding: 1rem 1.25rem;">
      <div style="display: flex; justify-content: space-between; align-items: flex-start; margin-bottom: 8px;">
        <h3 style="font-size: 15px; font-weight: 500; margin: 0; color: var(--text-primary);">${escapeHtml(memo.title)}</h3>
        <button 
          onclick="deleteMemo(${memo.id})"
          style="background: none; border: none; color: var(--text-secondary); cursor: pointer; padding: 4px; font-size: 16px;"
          title="삭제"
        >
          <i class="ti ti-trash" style="font-size: 16px;"></i>
        </button>
      </div>
      <p style="font-size: 14px; color: var(--text-secondary); margin: 0; white-space: pre-wrap; line-height: 1.5;">${escapeHtml(memo.content)}</p>
    </div>
  `).join('');

  if (filtered.length === 0 && query !== '') {
    memoList.innerHTML = `<div style="text-align: center; padding: 2rem 1rem; color: var(--text-secondary); font-size: 14px;">"${escapeHtml(query)}"에 맞는 메모가 없습니다</div>`;
  }
}

function addMemo() {
  addForm.style.display = 'block';
  document.getElementById('newTitle').focus();
}

function cancelAdd() {
  addForm.style.display = 'none';
  document.getElementById('newTitle').value = '';
  document.getElementById('newContent').value = '';
}

function saveMemo() {
  const title = document.getElementById('newTitle').value.trim();
  const content = document.getElementById('newContent').value.trim();
  
  if (!title || !content) {
    alert('제목과 본문을 입력해주세요');
    return;
  }
  
  memos.push({ id: nextId++, title, content });
  cancelAdd();
  filterAndDisplay(searchInput.value.toLowerCase().trim());
}

function deleteMemo(id) {
  memos = memos.filter(m => m.id !== id);
  filterAndDisplay(searchInput.value.toLowerCase().trim());
}

function escapeHtml(text) {
  const div = document.createElement('div');
  div.textContent = text;
  return div.innerHTML;
}

filterAndDisplay('');
</script>
```
문제점

1. 개발자는 sql의 형태로 데이터를 저장하고 싶었지만, 컨텍스트가 부족해 html로 구현되었다.
2. 메모를 필터링하거나 검색할 수 있는 기능을 요청하지 않아 구현되지 않았으며 활용성이 떨어진다.
3. UI/UX에 대한 지침이 없었고, CSS를 적용하지 않은 디자인이 되었다.

| | 확인 항목 | 결과 |
| :-: | :-- | :-- |
| ① | 실행 성공까지 걸린 시간 | 측정불가 |
| ② | 없는 함수·컬럼을 지어낸 개수 | 함수: 6개 / 컬럼 사용안함 |
| | → 지어낸 이름 | filterAndDisplay, addMemo, cancelAdd, saveMemo, deleteMemo, escapeHtml |
| ③ | `CONVENTIONS.md` 위반 개수 | 제시 안함 |
| | → 무엇을 어겼는가 | |
| ④ | 사람이 직접 고친 지점 | 0곳 |
| | → 어디를 어떻게 | |
| ⑤ | **본인 메모만 반환되는가** | 예 (유저 기능 없음) |

## 방식 B — 4단계 분해 / spec → context → unit → verify

프롬프트
```[지시]
메모 검색 기능을 추가해줘. 제목과 본문에서 키워드로 검색된다.

[규약]
# 프로젝트 규약

이 문서는 코드를 작성할 때 지켜야 할 규칙입니다.

## 계층 분리

- `routes.js`는 HTTP 요청과 응답만 다룹니다. SQL을 직접 쓰지 않습니다.
- 데이터베이스 접근은 `service.js`에만 둡니다.

## 응답 형식

모든 응답은 다음 두 형태 중 하나입니다.

{ "ok": true,  "data": ... }
{ "ok": false, "error": "ERROR_CODE" }

에러 코드는 대문자와 밑줄로 씁니다. (예: `MEMO_NOT_FOUND`)

## 명명 규칙

- 함수명은 동사로 시작합니다. `list`, `get`, `create`, `update`, `remove`
- 데이터베이스 컬럼은 스네이크 케이스를 씁니다. `user_id`, `created_at`
- 자바스크립트 변수는 카멜 케이스를 씁니다. `userId`, `createdAt`

## 입력 검증

- 사용자 입력은 반드시 검증합니다.
- 검증에 실패하면 400과 함께 `{ ok: false, error }` 를 반환합니다.

## 권한

- 모든 조회와 수정은 **본인 소유 데이터로 한정**합니다.
- 모든 쿼리에 `user_id` 조건을 포함합니다.

[근거]
(schema.sql)
-- memo-seed 데이터베이스 스키마

CREATE TABLE users (
  id         INTEGER PRIMARY KEY,
  email      TEXT NOT NULL UNIQUE,
  name       TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE memos (
  id         INTEGER PRIMARY KEY,
  user_id    INTEGER NOT NULL,
  title      TEXT NOT NULL,
  body       TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY (user_id) REFERENCES users(id)
);

CREATE INDEX idx_memos_user ON memos(user_id);


(service.js)
const db = require('./db');

/**
 * 사용자의 메모 목록을 최신순으로 조회한다.
 */
function listMemos(userId) {
  return db.all(
    `SELECT id, title, created_at
       FROM memos
      WHERE user_id = ?
      ORDER BY created_at DESC`,
    [userId]
  );
}

/**
 * 메모 한 건을 조회한다. 본인 메모가 아니면 null을 반환한다.
 */
function getMemo(userId, memoId) {
  return db.get(
    `SELECT id, title, body, created_at
       FROM memos
      WHERE id = ? AND user_id = ?`,
    [memoId, userId]
  );
}

/**
 * 메모를 생성한다.
 */
function createMemo(userId, title, body) {
  return db.run(
    `INSERT INTO memos (user_id, title, body, created_at)
     VALUES (?, ?, ?, datetime('now'))`,
    [userId, title, body]
  );
}

module.exports = { listMemos, getMemo, createMemo };


(routes.js)
const express = require('express');
const service = require('./service');

const router = express.Router();

// 메모 목록 조회
router.get('/memos', async (req, res) => {
  const memos = await service.listMemos(req.user.id);
  res.json({ ok: true, data: memos });
});

// 메모 단건 조회
router.get('/memos/:id', async (req, res) => {
  const memo = await service.getMemo(req.user.id, req.params.id);

  if (!memo) {
    return res.status(404).json({ ok: false, error: 'MEMO_NOT_FOUND' });
  }

  res.json({ ok: true, data: memo });
});

// 메모 생성
router.post('/memos', async (req, res) => {
  const { title, body } = req.body;

  if (!title || !body) {
    return res.status(400).json({ ok: false, error: 'TITLE_AND_BODY_REQUIRED' });
  }

  const result = await service.createMemo(req.user.id, title, body);
  res.status(201).json({ ok: true, data: { id: result.lastID } });
});

module.exports = router;

[종료조건]
- GET /memos/search?q=키워드 로 호출된다
- 제목 또는 본문에 키워드가 포함된 메모만 반환한다
- 본인 메모만 반환한다
- q가 비어 있으면 400과 { ok: false, error } 를 반환한다
```

결과 ⓐ - service.js
```const db = require('./db');

/**
 * 사용자의 메모 목록을 최신순으로 조회한다.
 */
function listMemos(userId) {
  return db.all(
    `SELECT id, title, created_at
       FROM memos
      WHERE user_id = ?
      ORDER BY created_at DESC`,
    [userId]
  );
}

/**
 * 메모 한 건을 조회한다. 본인 메모가 아니면 null을 반환한다.
 */
function getMemo(userId, memoId) {
  return db.get(
    `SELECT id, title, body, created_at
       FROM memos
      WHERE id = ? AND user_id = ?`,
    [memoId, userId]
  );
}

/**
 * 메모를 생성한다.
 */
function createMemo(userId, title, body) {
  return db.run(
    `INSERT INTO memos (user_id, title, body, created_at)
     VALUES (?, ?, ?, datetime('now'))`,
    [userId, title, body]
  );
}

/**
 * 키워드로 메모를 검색한다. 제목 또는 본문에 포함된 메모를 반환한다.
 */
function searchMemos(userId, query) {
  const searchPattern = `%${query}%`;
  return db.all(
    `SELECT id, title, created_at
       FROM memos
      WHERE user_id = ? AND (title LIKE ? OR body LIKE ?)
      ORDER BY created_at DESC`,
    [userId, searchPattern, searchPattern]
  );
}

module.exports = { listMemos, getMemo, createMemo, searchMemos };
```

결과 ⓑ - routes.js
```const express = require('express');
const service = require('./service');

const router = express.Router();

// 메모 목록 조회
router.get('/memos', async (req, res) => {
  const memos = await service.listMemos(req.user.id);
  res.json({ ok: true, data: memos });
});

// 메모 검색
router.get('/memos/search', async (req, res) => {
  const { q } = req.query;

  if (!q || q.trim() === '') {
    return res.status(400).json({ ok: false, error: 'QUERY_REQUIRED' });
  }

  const memos = await service.searchMemos(req.user.id, q.trim());
  res.json({ ok: true, data: memos });
});

// 메모 단건 조회
router.get('/memos/:id', async (req, res) => {
  const memo = await service.getMemo(req.user.id, req.params.id);

  if (!memo) {
    return res.status(404).json({ ok: false, error: 'MEMO_NOT_FOUND' });
  }

  res.json({ ok: true, data: memo });
});

// 메모 생성
router.post('/memos', async (req, res) => {
  const { title, body } = req.body;

  if (!title || !body) {
    return res.status(400).json({ ok: false, error: 'TITLE_AND_BODY_REQUIRED' });
  }

  const result = await service.createMemo(req.user.id, title, body);
  res.status(201).json({ ok: true, data: { id: result.lastID } });
});

module.exports = router;
```

| | 확인 항목 | 결과 |
| :-: | :-- | :-- |
| ① | 실행 성공까지 걸린 시간 | 약 7초 |
| ② | 없는 함수·컬럼을 지어낸 개수 | 1건(함수 1건, 컬럼은 기존 컬럼 모두 그대로 사용됨) |
| | → 지어낸 이름 | searchMemos(userId, query) |
| ③ | `CONVENTIONS.md` 위반 개수 | 0개 |
| | → 무엇을 어겼는가 | 해당 없음 |
| ④ | 사람이 직접 고친 지점 | 0곳 |
| | → 어디를 어떻게 | |
| ⑤ | **본인 메모만 반환되는가** | 예(SQL상 user_id 기준으로 선별함) |


## 두 방식의 차이 / Difference

**4-1. 두 결과의 가장 큰 차이는 무엇입니까?**

```

```

**4-2. A조의 실패는 모델 탓입니까, 우리가 주지 않은 탓입니까? 근거를 들어 적으세요.**

```
우리가 주지 않은 탓이다.

어떤 형태의 서비스를, 어떤 기술을 통해 구현할 지에 대한 방법에 대해 제시하지 않았다.
때문에 의도했던 기능과 맥락을 AI가 이해하지 못했고, 원하는 결과를 얻지 못했다.

만약 SQL의 모델과 스키마를 제시하고, 메모 서비스의 함수와 기능에 대한 명세를 제시했다면 원하는 형태가 되지 않았을까?
```

**4-3. B조가 준 자료 중 결과를 가장 크게 바꾼 것 하나를 꼽는다면 무엇입니까? 왜 그렇게 생각합니까?**

```

```


## 내가 개입해야 했던 지점 / Where you intervened



---

> 수업 종료 시 커밋하세요 / Commit this at the end of class
> `git add docs/week-02.md && git commit -m "docs: 2주차 활동지 작성"`
