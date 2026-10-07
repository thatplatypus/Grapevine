Fixtures for the tests of the shim's file reading: every byte value once, and nothing at all.

`served/` is a directory that the tests of file responses and static files serve from:
plain files, one larger than the 64 KB a file is read in, hidden files, a link to a file
inside it, links to a file and to a directory outside it, a link to nothing, and a small
site. `outside/` is what those links must not let anyone read. The build sets the time
`served/a.txt` was changed to 6 November 1994, 08:49:37 GMT.
