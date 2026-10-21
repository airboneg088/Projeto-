-- Desfaz 20261021002900_storage.sql.
-- Atenção no hospedado: o bucket precisa estar vazio, e arquivos devem ser
-- removidos pela API de Storage (apagar direto em storage.objects deixa o
-- arquivo órfão no armazenamento).

drop policy references_insert_manager on storage.objects;
drop policy evidences_insert_performer on storage.objects;

drop function public.can_read_reference(text);
drop function public.can_read_evidence(text);
drop function private.can_read_reference_object(text);
drop function private.can_insert_reference_object(text);
drop function private.can_read_evidence_object(text);
drop function private.can_insert_evidence_object(text);

delete from storage.buckets where id in ('evidences', 'references');
