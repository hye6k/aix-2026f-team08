# AI 협업 기록 / AI Collaboration Log

작성 원칙: 프롬프트 나열이 아니라 **판단 근거**를 남긴다.
Principle: record your **reasoning**, not just prompts.

---

## [이슈 #1] 메모 검색 기능

**목표(스펙) / Spec**
- 입력 Input: 검색 키워드
- 처리 Processing: 메모의 제목 또는 본문에서 키워드 검색
- 출력 Output: 조건에 맞는 메모 목록
- 실패 조건 Failure: 

**요청한 프롬프트 요지 / Prompt (summary)**

메모의 제목과 본문에서 키워드를 검색하는 기능을 요청했다.
방식 A는 기능 요구만 제시했고, 방식 B는 프로젝트 규약, 기존 코드, 데이터베이스 스키마, 종료 조건을 함께 제시했다.

**결과에 대한 판단 / Decisions**
- 채택한 부분과 이유 / Accepted, because: 해당 없음
- 수정한 부분과 이유 / Changed, because: 해당 없음
- 폐기한 부분과 이유 / Rejected, because: 해당 없음

방식 A는 검색 기능 자체는 구현했지만 독립적인 HTML/JavaScript 애플리케이션 형태로 작성되었다.

방식 B는 기존 service.js, routes.js, 데이터베이스 구조를 반영해 검색 기능을 추가했다. 또한 user_id 조건과 빈 검색어 검증이 포함되었다.

**검증 방법 / How it was verified**

- 제목과 본문 검색 여부 확인
- 기존 코드 구조 반영 여부 확인
- user_id 조건 포함 여부 확인
- 빈 검색어 처리 여부 확인
- 프로젝트 규약 준수 여부 확인

---

## [이슈 #__] 제목 / Title

**목표(스펙) / Spec**
- 입력 Input:
- 처리 Processing:
- 출력 Output:
- 실패 조건 Failure:

**요청한 프롬프트 요지 / Prompt (summary)**

**결과에 대한 판단 / Decisions**
- 채택한 부분과 이유 / Accepted, because:
- 수정한 부분과 이유 / Changed, because:
- 폐기한 부분과 이유 / Rejected, because:

**검증 방법 / How it was verified**

---
(이슈 단위로 반복 / repeat per issue)
