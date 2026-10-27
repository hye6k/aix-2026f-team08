# 6주차 활동지 / Week 6 Worksheet

**저장소와 첫 PR / Repository and first pull request**

- 작성일 / Date: 2026년 10월 6일
- 참여자 / Present: 강동혁, 박제헌, 오형석
- 최종 반영 / Feeds into: 제출물 ① 저장소 / Submission ①

---

## 초기 파일 / Initial files

- [x] README
- [x] LICENSE
- [x] .gitignore

## 팀원 초대 수락 / Invitations accepted

- [x] 전원 All

## 브랜치 이름 규칙 / Branch naming rule

브랜치 이름은 `<종류>/<GitHub 이슈 번호>-<작업 내용>` 형식을 사용한다. 종류는 `feat`, `fix`, `docs`, `refactor`, `chore`, `test`로 구분하고, 작업 내용은 영문 소문자와 하이픈으로 작성한다.

각 작업은 최신 main에서 새 브랜치를 만들어 진행하며, 하나의 브랜치에는 하나의 작업 목적을 담는다. PR 리뷰와 병합이 완료되면 해당 브랜치를 삭제한다.

예: `feat/12-wake-confirmation`, `docs/14-week06` (번호는 형식 예시)


## 커밋 메시지 규칙 / Commit message rule

커밋 메시지는 `<종류>: <변경 내용>` 형식을 사용한다. 종류는 `feat`, `fix`, `docs`, `refactor`, `test`, `chore`로 구분하고, 변경 내용은 한국어로 구체적이고 간결하게 작성한다.

하나의 커밋에는 하나의 변경 목적을 담는다. 변경 이유나 제약에 대한 설명이 필요하면 제목 아래 한 줄을 비우고 본문에 작성한다. 이슈 번호는 선택 사항이며, 관련 이슈는 PR에 연결한다.

예: `feat: 기상 후보 확인 기능 추가`, `docs: 6주차 활동지 작성`


## 각자 PR 번호 / 리뷰어 / Each member's PR / reviewer



## 브랜치 보호 설정 / Branch protection

- [ ] 설정 완료 Done

브랜치 보호는 본격적인 개발을 시작하는 시점부터 적용한다.

## 성찰 / Reflection — 리뷰가 형식적이지 않으려면

아직 첫 PR 리뷰 전이므로 다음을 리뷰 기준으로 정한다. 작성자는 관련 이슈, 변경 이유, 확인 방법과 결과, 남은 제약을 PR에 적는다. 리뷰어는 코드의 모양뿐 아니라 이슈의 완료 조건을 만족하는지 확인하고, 어떤 입력이나 상황을 검토했는지 구체적으로 남긴다.

이 프로젝트에서는 알람 해제와 기상 확정의 구분, 자정을 넘는 계산, 중복 이벤트 처리, 권한 거부 상황을 우선 검토한다. 실제 Android 기기에서 확인한 결과와 테스트 이벤트로 확인한 결과를 구분한다. AI가 작성한 코드도 작성자가 동작과 검증 결과를 설명할 수 있어야 한다.

리뷰에서 발견한 오류와 규칙의 개선점은 첫 PR 병합 후 실제 사례를 바탕으로 추가한다.


---

> 수업 종료 시 커밋하세요 / Commit this at the end of class
> `git add docs/week-06.md && git commit -m "docs: 6주차 활동지 작성"`
