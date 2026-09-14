-- Forward repair for explicitly raised optimistic/business conflicts only.
-- These 51 definitions are pinned to the preceding committed migration history.
-- Normalized body hashes stop on drift; CREATE OR REPLACE preserves OIDs/ACLs.
-- Authorization, locks, version comparisons and real serialization errors stay intact.
begin;
do $repair$
declare
  expected record;
  target oid;
  body text;
  definition text;
begin
  for expected in select * from (values
    ('public.accept_active_list_invitation(uuid,bigint)', '4a1de9467df4a35a4e92c793609d57d6', 2),
    ('public.accept_friend_request(uuid,bigint)', 'd6478e1dfcd901156c2408da9af5b399', 1),
    ('public.accept_template_send(uuid,bigint,uuid)', 'c8e7bc9cf30c6cb8d41c33bd78727a2a', 1),
    ('public.block_profile(uuid)', '7964804251947c2a708d68fa540dd557', 1),
    ('public.cancel_active_list_invitation(uuid,uuid,bigint)', '657a8366ba69f1a58cd736f50dff1358', 1),
    ('public.cancel_friend_request(uuid,bigint)', '326795e93ee3c33486dd2ef7cffaaa1d', 1),
    ('public.change_active_list_split_currency(uuid,text,bigint)', '072948108712dfd2220c82604b96ddc9', 1),
    ('public.copy_public_template(uuid,bigint,uuid)', '9adac6ecd67c615460529ba92b836772', 1),
    ('public.create_active_list_expense_v2(uuid,text,bigint,uuid,uuid[],bigint[],uuid,bigint)', '115518a18231ecb7131f458e15b782b9', 2),
    ('public.create_active_list_from_template(uuid,uuid[],text,uuid,uuid[],bigint)', 'de2da0fe6064c3dc10e13a99448eba3d', 1),
    ('public.create_active_list_item_v2(uuid,text,uuid,bigint,uuid[],bigint,text)', '903b51960753e7e3fa102a21c8d3346f', 2),
    ('public.create_active_list_item(uuid,text,uuid,bigint,bigint,text)', 'dcd5a3a92487eeb283cd53b784e31d22', 2),
    ('public.create_private_template_item(uuid,text,uuid,bigint,bigint)', '902b260043796c33b68ce101a9ed9992', 2),
    ('public.decline_active_list_invitation(uuid,bigint)', '4a7720d2c53cac64240bc1df15220dee', 2),
    ('public.decline_friend_request(uuid,bigint)', '4b20cc113e2b1277cb54df1a604928b6', 1),
    ('public.delete_active_list_expense(uuid,uuid,bigint,bigint)', '4deb063c918cb234daf3840806d8dcac', 2),
    ('public.delete_active_list_item(uuid,uuid,bigint,bigint)', 'b4d2dc3fc65023921e7e5cacf6d2ad7d', 1),
    ('public.delete_active_list(uuid,bigint)', 'f08b16914f1ef92655946f9b90143936', 1),
    ('public.delete_private_template_item(uuid,uuid,bigint,bigint)', 'f5b0ccb11a25a4e9a2d2211606638371', 1),
    ('public.delete_private_template(uuid,bigint)', 'b147419331c15a3886a764781597462c', 1),
    ('public.delete_template_category(uuid,bigint)', 'acd22b9b7873ddfbb2615556fcd95199', 1),
    ('public.enable_active_list_split(uuid,text,bigint)', 'a4acbe62eca1129c2b388f37a14795dd', 2),
    ('public.end_friendship(uuid,bigint)', 'b22266bd8f0e2461970858d4f4374f9a', 1),
    ('public.import_private_template_items(uuid,uuid[],uuid,uuid[],bigint,bigint)', 'ab6c744230632de0e2ad60b4b7bae5bb', 2),
    ('public.invite_active_list_member(uuid,uuid,bigint)', '9599751833aa8cb82c17b19b7d7d63c4', 2),
    ('public.leave_active_list(uuid,bigint)', 'a9bcba0aa490a5482ebdcccd4045553a', 3),
    ('public.moderate_public_template_report_group(uuid,text,bigint,bigint,text,text,uuid)', '7e3bcd254c3646385dfd5825b32e252c', 2),
    ('private.resolve_template_send(uuid,bigint,uuid,text)', '30bf734a1b7c7872c14838e93f4c8c99', 1),
    ('public.record_active_list_settlement(uuid,uuid,uuid,bigint,text,uuid,bigint)', 'f1a451b63a18310acfe9fedb8a7212c4', 2),
    ('public.remove_active_list_member(uuid,uuid,bigint)', 'c6584a774558e65dd7e8ba53a3072aac', 2),
    ('public.rename_active_list(uuid,text,bigint)', 'e5924a5c1591f1c0564718fc33152667', 1),
    ('public.rename_template_category(uuid,text,bigint)', 'b82aee4671bfa40ab546721509c8f84e', 1),
    ('public.reorder_active_list_items(uuid,uuid[],bigint)', 'd064fa346628b78c8683bb37c05bc9ca', 1),
    ('public.reorder_private_template_items(uuid,uuid[],bigint)', '6493e3b68c682a9f2f89dfe465ebdfa4', 1),
    ('public.report_public_template(uuid,bigint,text,text)', '97a58c19045886919d1f2e16aba76a66', 1),
    ('public.restore_public_template_moderation(uuid,bigint,bigint,text,uuid)', '07380e492cdf3c5016444dffada3b549', 2),
    ('public.reverse_active_list_settlement(uuid,uuid,text,uuid,bigint)', 'd7eb681df1d6c644ec61d9e8ffa0c618', 5),
    ('public.save_active_list_as_template(uuid,uuid[],text,uuid,uuid,bigint)', 'e91c205f48a24c554e7cfd4085f7a182', 1),
    ('public.send_friend_request(uuid,bigint)', '55ad349401f0f04c150b86b16e4e5ece', 2),
    ('public.send_template_to_friend(uuid,uuid,bigint,uuid)', '0988e5f7fd5d5eebf79ab50ba2e557b6', 1),
    ('public.set_active_list_archived(uuid,boolean,bigint)', '66856f03d4d4df2e489b04b5cb59df1c', 1),
    ('public.set_active_list_item_completed(uuid,uuid,boolean,bigint,bigint)', '7994d8c1aced3a32ae84ba58fd3480fe', 1),
    ('public.set_template_publication(uuid,boolean,bigint)', 'f01dda8a5d9818912cffce596620e0b7', 1),
    ('public.transfer_active_list_ownership(uuid,uuid,bigint,bigint)', 'b66f7cf9c8b2c4542c7ef7bdebbf4bfb', 2),
    ('public.update_active_list_expense_v2(uuid,uuid,text,bigint,uuid,uuid[],bigint[],bigint,bigint)', 'f1b47655d35951f76496ed0d42eef763', 2),
    ('public.update_active_list_expense(uuid,uuid,text,bigint,uuid,uuid[],bigint,bigint)', '556ad2f9484a0db0cc22e3d47ef1f7ac', 2),
    ('public.update_active_list_general_note(uuid,text,uuid[],bigint)', 'b7ffbebe8c98762ae124889ec6abfe6f', 3),
    ('public.update_active_list_item_v2(uuid,uuid,text,bigint,text,uuid[],bigint,bigint)', '8cb25488828238141928f7733cd8d92a', 1),
    ('public.update_active_list_item(uuid,uuid,text,bigint,text,bigint,bigint)', '769fec8e9e4e24e1c044644655abf5c8', 1),
    ('public.update_private_template_item(uuid,uuid,text,bigint,bigint,bigint)', '5e2e63768d2934a18ebb937e2fa2d366', 1),
    ('public.update_private_template(uuid,text,uuid,bigint)', '937abcfce9640912dd85b938d9e9ce41', 1)
  ) as reviewed(signature, body_md5, conflict_count)
  loop
    target := to_regprocedure(expected.signature);
    select replace(prosrc, chr(13), '') into body from pg_proc where oid = target;
    if target is null or md5(body) is distinct from expected.body_md5 then
      raise exception 'Business-conflict definition drift: %', expected.signature;
    end if;
    if (length(body) - length(replace(body, '40001', ''))) / 5 <> expected.conflict_count then
      raise exception 'Unexpected conflict count: %', expected.signature;
    end if;
    definition := pg_get_functiondef(target);
    -- Exact RAISE option in the reviewed bodies, not SQLSTATE handlers or
    -- a global replacement of engine-originated serialization failures.
    definition := replace(definition, 'errcode = ''40001''', 'errcode = ''PT409''');
    execute definition;
  end loop;
end;
$repair$;
commit;
