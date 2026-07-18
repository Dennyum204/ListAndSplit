create policy "user_blocks_reject_direct_client_access"
on public.user_blocks
as restrictive
for all
to anon, authenticated
using (false)
with check (false);
