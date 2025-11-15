create policy "Anyone can view store logos"
on "storage"."objects"
as permissive
for select
to public
using ((bucket_id = 'store-logos'::text));


create policy "Authenticated users can upload images"
on "storage"."objects"
as permissive
for insert
to public
with check (((bucket_id = 'product-images'::text) AND (auth.role() = 'authenticated'::text)));


create policy "Authenticated users can upload store logos"
on "storage"."objects"
as permissive
for insert
to public
with check (((bucket_id = 'store-logos'::text) AND (auth.role() = 'authenticated'::text)));


create policy "Public Access"
on "storage"."objects"
as permissive
for select
to public
using ((bucket_id = 'product-images'::text));


create policy "Users can delete own images"
on "storage"."objects"
as permissive
for delete
to public
using (((bucket_id = 'product-images'::text) AND ((auth.uid())::text = (storage.foldername(name))[1])));


create policy "Users can delete their own avatars"
on "storage"."objects"
as permissive
for delete
to public
using (((bucket_id = 'avatars'::text) AND ((auth.uid())::text = (storage.foldername(name))[1])));


create policy "Users can delete their own store logos"
on "storage"."objects"
as permissive
for delete
to public
using (((bucket_id = 'store-logos'::text) AND ((auth.uid())::text = (storage.foldername(name))[1])));


create policy "Users can update own images"
on "storage"."objects"
as permissive
for update
to public
using (((bucket_id = 'product-images'::text) AND ((auth.uid())::text = (storage.foldername(name))[1])));


create policy "Users can update their own avatars"
on "storage"."objects"
as permissive
for update
to public
using (((bucket_id = 'avatars'::text) AND ((auth.uid())::text = (storage.foldername(name))[1])));


create policy "Users can update their own store logos"
on "storage"."objects"
as permissive
for update
to public
using (((bucket_id = 'store-logos'::text) AND ((auth.uid())::text = (storage.foldername(name))[1])));


create policy "Users can upload their own avatars"
on "storage"."objects"
as permissive
for insert
to public
with check (((bucket_id = 'avatars'::text) AND ((auth.uid())::text = (storage.foldername(name))[1])));


create policy "Users can view all avatars"
on "storage"."objects"
as permissive
for select
to public
using ((bucket_id = 'avatars'::text));



