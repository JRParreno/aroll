from sqlalchemy import text
from app.db.session import SessionLocal

db = SessionLocal()
try:
    rows = db.execute(
        text(
            """
            SELECT e.full_name, cr.consent_type, cr.policy_version, cr.content_source,
                   cr.document_id::text AS document_id
            FROM consent_record cr
            JOIN employee e ON e.id = cr.employee_id
            WHERE e.full_name = 'Drew Gabriel'
            ORDER BY cr.created_at
            """
        )
    ).mappings().all()
    for r in rows:
        print(dict(r))
    docs = db.execute(
        text(
            """
            SELECT id::text, consent_type, version, scope, business_id::text
            FROM consent_document
            WHERE id IN (
              'b0dd4f3d-46ca-4116-b14b-3a393fdd2bc5',
              '0026c06a-68fd-4fb2-8da4-28c42950a214',
              '83e1eb9d-ecaa-444c-93fa-c2564caf94e7'
            )
            """
        )
    ).mappings().all()
    print("--- docs ---")
    for d in docs:
        print(dict(d))
finally:
    db.close()
