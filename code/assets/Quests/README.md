# Quest changes (no story on the server)

- `original/` – the game's own quest files we change, as extracted from the game.
- `edited/` – our changed versions, as WolvenKit JSON (same paths, `.json` added).

The "Build quest archive" workflow turns `original/` into JSON (to see and edit
it) and builds `edited/` into `zz_NightCityOnline_NoStory.archive`, both pushed
to the `quest-ci` branch. The archive is installed only with the server's mods,
so single player is untouched.

## What's changed

`base/quest/cyberpunk2077.questphase` (the master quest): the inputs of the
story phases (prologue, act 1, epilogue, final boards) and of the side-job and
minor-quest phases are renamed `MP_OFF_...`, so nothing can start them. Nothing
else is touched: open-world content (shops, travel, apartments, world
activities), bugfixing and the rest still run. Undo = delete the archive.

`base/open_world/phases/open_world_content.questphase`: the inputs of fixer
gigs, minor activities (NCPD scanner hustles, cyberpsychos), combat events and
street stories are renamed `MP_OFF_...`. Vendors, fast travel, the metro, radio,
city life, cars and the rest are untouched.
