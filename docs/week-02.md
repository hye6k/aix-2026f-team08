# 2주차 활동지 / Week 2 Worksheet

**AI 협업 방식 비교 / Comparing two ways of working with AI**

- 작성일 / Date: 
- 참여자 / Present: 
- 결과보고서 / Report chapter: 6장 AI 활용과 판단
- 최종 반영 / Feeds into: PROMPTS.md 첫 항목

---

## 구현할 작은 기능 / Small feature



## 사용한 도구 / Tool used



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



## 두 방식의 차이 / Difference



## 내가 개입해야 했던 지점 / Where you intervened



---

> 수업 종료 시 커밋하세요 / Commit this at the end of class
> `git add docs/week-02.md && git commit -m "docs: 2주차 활동지 작성"`
