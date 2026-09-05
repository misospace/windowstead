# Changelog

## [0.0.22](https://github.com/misospace/windowstead/compare/0.0.21...0.0.22) (2026-09-05)


### Bug Fixes

* 329: Validate reserved_resources, milestone, and build-id fields in save schema ([#336](https://github.com/misospace/windowstead/issues/336)) ([8035fe6](https://github.com/misospace/windowstead/commit/8035fe6e7287fe0a446379815837a9cc404d65ea)), closes [#329](https://github.com/misospace/windowstead/issues/329)
* 330: ambient break event leaked gather reservations ([#337](https://github.com/misospace/windowstead/issues/337)) ([109d2fd](https://github.com/misospace/windowstead/commit/109d2fd30e6eeb5567dfaef772098cdb7a8a54e3)), closes [#330](https://github.com/misospace/windowstead/issues/330)
* 349 ([#354](https://github.com/misospace/windowstead/issues/354)) ([4183164](https://github.com/misospace/windowstead/commit/418316494cc2afe3de33c543bd75357a8dc90f1c)), closes [#349](https://github.com/misospace/windowstead/issues/349)
* **colony:** refund carried resources and release build reservation on ambient break ([#367](https://github.com/misospace/windowstead/issues/367)) ([81babb2](https://github.com/misospace/windowstead/commit/81babb2416ecc6d19380d958efa0abfb4d5add0f)), closes [#363](https://github.com/misospace/windowstead/issues/363)
* **overlay:** key worker sprites by stable identity, not array index ([#372](https://github.com/misospace/windowstead/issues/372)) ([0297b3b](https://github.com/misospace/windowstead/commit/0297b3b4922a0f48b0715f7ca1cb5b7b6a229f1e)), closes [#364](https://github.com/misospace/windowstead/issues/364)
* **persist:** stamp save_version before saving and remove dead code ([#352](https://github.com/misospace/windowstead/issues/352)) ([4be3647](https://github.com/misospace/windowstead/commit/4be3647bdbebe8fd44a23493b795867504feebb2)), closes [#345](https://github.com/misospace/windowstead/issues/345)


### Performance Improvements

* **main:** cache event-drawer expanded-log text across event_rev bumps ([#371](https://github.com/misospace/windowstead/issues/371)) ([c98850a](https://github.com/misospace/windowstead/commit/c98850a55372717bc26250a3ba63c1b6eb1fe6aa)), closes [#361](https://github.com/misospace/windowstead/issues/361)


### Chores

* bump Godot toolchain to 4.7.1 ([#322](https://github.com/misospace/windowstead/issues/322)) ([71c3c53](https://github.com/misospace/windowstead/commit/71c3c5391f3c1be4874174835208566c6c9f5aa3))
* complete Godot toolchain bump from 4.2.2 to 4.7.1 ([#328](https://github.com/misospace/windowstead/issues/328)) ([2468a93](https://github.com/misospace/windowstead/commit/2468a938a93a55350feeeaa4c915f732cf8c3fc0)), closes [#314](https://github.com/misospace/windowstead/issues/314)
* **release:** verify export artifacts exist and are non-empty before upload ([#374](https://github.com/misospace/windowstead/issues/374)) ([c4eddd2](https://github.com/misospace/windowstead/commit/c4eddd2fcc7d83e8a806be17c827e76cb61a3605)), closes [#366](https://github.com/misospace/windowstead/issues/366)
* **scripts:** move prune-stale-branches.sh into scripts/bin/ ([#370](https://github.com/misospace/windowstead/issues/370)) ([5e1b71b](https://github.com/misospace/windowstead/commit/5e1b71bd257d6bc8ff3d1dd12acf9c9c7b9830d7)), closes [#360](https://github.com/misospace/windowstead/issues/360)
* **workflows:** standardize GitHub App secret names to BOT_* ([#373](https://github.com/misospace/windowstead/issues/373)) ([4cd6399](https://github.com/misospace/windowstead/commit/4cd63996985f6c68b90b85d6e2d3bbd41d716790)), closes [#365](https://github.com/misospace/windowstead/issues/365)


### Documentation

* issue contract for the autonomous loop (template + AGENTS.md) ([#324](https://github.com/misospace/windowstead/issues/324)) ([35f11ef](https://github.com/misospace/windowstead/commit/35f11effc5dede21f89b3f5a04fbda3f7d7d3503))
* record the testing traps the loop learned ([#323](https://github.com/misospace/windowstead/issues/323)) ([aecf793](https://github.com/misospace/windowstead/commit/aecf793043816ab97a5e569ce1ef39294974da65))


### Refactors

* Replace deprecated % string formatting in game_state.gd print statements ([#304](https://github.com/misospace/windowstead/issues/304)) ([146f46a](https://github.com/misospace/windowstead/commit/146f46a7cfd9066f9e8ef20a4127d380ea13599a)), closes [#295](https://github.com/misospace/windowstead/issues/295)
* **settings:** place Focus Mode and Zoom widgets in main.tscn ([#369](https://github.com/misospace/windowstead/issues/369)) ([2fb15ea](https://github.com/misospace/windowstead/commit/2fb15eafa55ff30586ad9fe921b95181c5d8acce)), closes [#359](https://github.com/misospace/windowstead/issues/359)
* **theme:** extract dock theme/style construction into dock_theme.gd ([#368](https://github.com/misospace/windowstead/issues/368)) ([383c823](https://github.com/misospace/windowstead/commit/383c823c303ec6b541cced288c29139e1411f9a3)), closes [#358](https://github.com/misospace/windowstead/issues/358)
