# 네이밍 규칙 — 호환 인덱스

> 기존 경로를 유지하는 호환 인덱스입니다. 실제 접두사, 언어, 작성자와 문서화 수준은 확정된 프로필이 결정합니다.

## 새 문서 라우팅

| 기존 내용 | 새 위치 |
|---|---|
| private/public/인터페이스/DTO/bool 명명 예시 | [네이밍·문서화 공통 규칙](core/naming-and-documentation.md) |
| `m_`, `func_`, 한글, `윤승종` 기본안 | [프로필이 결정하는 값](core/naming-and-documentation.md) |
| Allman Style, 공백 4칸, using·별칭 예시 | [포맷과 using 호환 지침](core/naming-and-documentation.md) |
| 한글 리전 예시와 기존 주석 보존 | [리전 정책](core/naming-and-documentation.md) |
| `[클래스명]` 로그와 XML 헤더 예시 | [로그·XML 정책](core/naming-and-documentation.md) |

## 호환 안내

기존 값은 프로필 예시의 기본 제안으로 보존했습니다. 프로젝트가 다른 값을 확정하면 `private_field_prefix`, `ui_callback_prefix`, `response_language`, `log_language`, `author_name`, `region_policy`, `xml_documentation_policy`가 우선합니다.

