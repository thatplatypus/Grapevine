#!/bin/sh
# What the image runs when it is given no command: the Todo sample, to be tried out.
#
# Whoever tries it out has no key and no password to give it, and a server without them
# starts only where app.environment is Development. So that is what this says, to a
# server that was told nothing of the kind. One whose environment is named is what it was
# called, and one that was given a config file is whatever the file makes it, which is a
# deployment unless the file says otherwise: a variable outranks the file, so setting one
# here would speak over a file that says Production.
#
# The same tests as the framework's own: a variable that is set to nothing is not set,
# and the file is the one GRAPEVINE_CONFIG names, or grapevine.json where the server runs.
if [ -z "${GRAPEVINE_APP_ENVIRONMENT:-}" ] && [ -z "${GRAPEVINE_CONFIG:-}" ] && [ ! -e grapevine.json ]; then
  export GRAPEVINE_APP_ENVIRONMENT=Development
fi
# In place of this shell, so that the server is the process a stop is sent to.
exec ./build/bin/todo-api
