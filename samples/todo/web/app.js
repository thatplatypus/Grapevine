// The page's whole behaviour, as one module. It asks its own server where the API is,
// and from then on talks to that origin: the one it came from, or another that allows it.
// Until it knows, it sends nothing anywhere.
//
// Nothing the API says is ever handed to the HTML parser. Every text goes into the page
// with textContent, so a title that reads like markup is shown as the text it is.

const form = document.getElementById('add-form');
const input = document.getElementById('title');
const message = document.getElementById('message');
const list = document.getElementById('todos');
const count = document.getElementById('count');
const row = document.getElementById('todo-row');
const apiOrigin = document.getElementById('api-origin');
const apiStatus = document.getElementById('api-status');
const filters = Array.from(document.querySelectorAll('[data-filter]'));
const signInForm = document.getElementById('sign-in-form');
const userInput = document.getElementById('user');
const passwordInput = document.getElementById('password');
const signedIn = document.getElementById('signed-in');
const who = document.getElementById('who');
const numbers = document.getElementById('numbers');
const signOutButton = document.getElementById('sign-out');
const accountMessage = document.getElementById('account-message');

const QUERY = { all: '', open: '?done=false', done: '?done=true' };
const NOTHING = { all: 'Nothing to do yet.', open: 'Nothing open.', done: 'Nothing done yet.' };
// How long an answer may take. Changes wait for one another, so one that never ended
// would hold up every change after it.
const PATIENCE = 30_000;

let filter = 'all';
let adding = false;
let waiting = 0;
let last = Promise.resolve();
// Who is signed in: a name, and the token the API gave for it. It is kept here and nowhere
// else: not in storage, not in a cookie, not in the address. A reload forgets it, and a
// script that found its way into the page later would find nothing put by for it.
let session = null;
let signingIn = false;

/** The API answered, and the answer was a refusal: a problem document, as a rule. */
class Refusal extends Error {
  constructor(status, detail, errors, requestId) {
    super(detail);
    this.status = status;
    this.errors = errors;
    this.requestId = requestId;
  }
}

/** No answer could be read: the API is not there, or the browser may not show this page its answers. */
class Unreachable extends Error {
  constructor(origin) {
    super();
    this.origin = origin;
  }
}

/** The API was asked, and PATIENCE went by without an answer. */
class Unanswered extends Error {
  constructor(origin) {
    super();
    this.origin = origin;
  }
}

/** The page's own server did not say where the API is, so there is nowhere to send anything. */
class Unconfigured extends Error {}

/**
 * Where the API is: an origin, or the empty text for the one the page came from. Asked
 * once, when the page loads. Every call waits for the answer, so nothing a person does in
 * the meantime goes to the wrong server, and a page that never learns it sends nothing.
 */
const whereTheApiIs = askWhereTheApiIs();
// Whoever waits for it is told when it fails. This only keeps the browser from reporting
// a failure that nobody has asked about yet.
whereTheApiIs.catch(() => {});

async function askWhereTheApiIs() {
  let response;
  try {
    response = await fetch('config.json', { cache: 'no-store' });
  } catch {
    throw new Unconfigured();
  }
  // A server that has no such file says nothing about it, and is its own API. Any other
  // failure says nothing either way, and guessing would send what a person types to a
  // server it was not meant for.
  if (response.status === 404) {
    return '';
  }
  let config = null;
  if (response.ok) {
    try {
      config = await response.json();
    } catch {
      // Not JSON: nothing was said.
    }
  }
  if (config === null || typeof config !== 'object' || typeof config.api !== 'string') {
    throw new Unconfigured();
  }
  return config.api;
}

/** A signal that gives up when PATIENCE has gone by, and what puts its clock away again. */
function patience() {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), PATIENCE);
  return { signal: controller.signal, over: () => clearTimeout(timer) };
}

async function call(method, path, body) {
  const api = await whereTheApiIs;
  const origin = api || location.origin;
  const waited = patience();
  const init = { method, headers: {}, signal: waited.signal };
  // Whoever is signed in when the request is sent. A sign-out that comes before the answer
  // does not change whose request this was.
  const carried = session;
  if (carried) {
    init.headers.Authorization = `Bearer ${carried.token}`;
  }
  if (body !== undefined) {
    init.headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(body);
  }

  try {
    let response;
    try {
      response = await fetch(api + path, init);
    } catch {
      if (waited.signal.aborted) {
        throw new Unanswered(origin);
      }
      // A failed connection and an answer the browser withholds from this origin look the
      // same from here, on purpose: a page is not told which.
      throw new Unreachable(origin);
    }

    if (!response.ok) {
      const refusal = await refusalOf(response);
      // The API no longer takes the token: it has ended, or the server has another key
      // since. Whoever was signed in is so no longer, and is told, unless someone else is
      // signed in by now or nobody is.
      if (response.status === 401 && carried && session === carried) {
        signedOutBy(refusal);
      }
      throw refusal;
    }
    try {
      return response.status === 204 ? null : await response.json();
    } catch (error) {
      // An answer that began and did not end in time is one that did not come.
      throw waited.signal.aborted ? new Unanswered(origin) : error;
    }
  } finally {
    waited.over();
  }
}

async function refusalOf(response) {
  // Readable from another origin only because the API's policy exposes the header.
  const requestId = response.headers.get('X-Request-Id');
  let problem = null;
  try {
    problem = await response.json();
  } catch {
    // Not JSON: the status has to do.
  }
  const detail = problem && typeof problem.detail === 'string'
    ? problem.detail
    : `The API answered ${response.status}.`;
  const errors = problem && problem.errors && typeof problem.errors === 'object' ? problem.errors : {};
  return new Refusal(response.status, detail, errors, requestId);
}

function line(text, className) {
  const p = document.createElement('p');
  p.textContent = text;
  if (className) {
    p.className = className;
  }
  return p;
}

/** Says something in one of the page's two places for it: the list's, or the sign-in's. */
function say(lines, wrong, place = message) {
  place.classList.toggle('wrong', wrong);
  place.replaceChildren(...lines);
}

function sayNothing(place = message) {
  say([], false, place);
}

/** What a refusal of the API says, line by line: its words, what it says of each field, and which request it was. */
function wordsOf(refusal) {
  const lines = [line(refusal.message)];
  for (const [field, problems] of Object.entries(refusal.errors)) {
    const said = Array.isArray(problems) ? problems.join(', ') : String(problems);
    lines.push(line(`${field}: ${said}`, 'field'));
  }
  if (refusal.requestId) {
    lines.push(line(`Request ${refusal.requestId}`, 'request'));
  }
  return lines;
}

function sayWhatWentWrong(error, place = message) {
  if (error instanceof Refusal) {
    say(wordsOf(error), true, place);
  } else if (error instanceof Unreachable) {
    say([
      line(`The API at ${error.origin} cannot be reached from this page.`),
      line(`If it is running, it may not allow pages from ${location.origin}.`),
    ], true, place);
  } else if (error instanceof Unanswered) {
    say([line(`The API at ${error.origin} did not answer in time.`)], true, place);
  } else if (error instanceof Unconfigured) {
    say([
      line('This page could not find out where its API is, so it sends nothing.'),
      line('Load the page again to have it ask once more.'),
    ], true, place);
  } else {
    say([line('Something went wrong in the page itself.')], true, place);
    throw error;
  }
}

/**
 * Shows who is signed in, or the sign-in when nobody is. The keyboard does not stay on a
 * control that is no longer shown: it goes to *next* when it was on one.
 */
function showSession(next) {
  const signed = session !== null;
  const leaving = signed ? signInForm : signedIn;
  const held = leaving.contains(document.activeElement);
  signInForm.hidden = signed;
  signedIn.hidden = !signed;
  who.textContent = signed ? `Signed in as ${session.user}` : '';
  if (!signed) {
    numbers.textContent = '';
  }
  if (held) {
    next.focus();
  }
}

/** The API refused the token that was sent with a request, so nobody is signed in any more. */
function signedOutBy(refusal) {
  session = null;
  showSession(userInput);
  say([line('You have been signed out.'), ...wordsOf(refusal)], true, accountMessage);
}

/**
 * Reads the list's numbers, which are for whoever is signed in. An answer for someone who
 * is signed in no longer is not shown, and neither is what went wrong with asking for it:
 * a sign-out has said what there was to say.
 */
async function refreshNumbers() {
  const asked = session;
  if (asked === null) {
    return;
  }
  let stats;
  try {
    stats = await call('GET', '/admin/stats');
  } catch (error) {
    if (session === asked) {
      sayWhatWentWrong(error, accountMessage);
    }
    return;
  }
  if (session === asked) {
    numbers.textContent = `${stats.total === 1 ? '1 todo' : `${stats.total} todos`}, ${stats.open} open`;
  }
}

function newRow(id) {
  const item = row.content.firstElementChild.cloneNode(true);
  const box = item.querySelector('input');
  item.dataset.id = String(id);
  box.addEventListener('change', () => change(() => call('PUT', `/todos/${id}`, { done: box.checked })));
  item.querySelector('.delete').addEventListener('click', () => change(() => call('DELETE', `/todos/${id}`)));
  return item;
}

function fill(item, todo) {
  item.classList.toggle('done', todo.done);
  item.querySelector('.title').textContent = todo.title;
  item.querySelector('input').checked = todo.done;
  // Said aloud, "Delete" alone does not say which.
  item.querySelector('.delete').setAttribute('aria-label', `Delete: ${todo.title}`);
}

/**
 * Shows the todos. A row that is still wanted is changed where it stands and not made
 * anew, so the keyboard stays on the control it was on. When the row it was on is gone,
 * its place goes to the same control of the row that moved up, or of the last row, or to
 * the field for a new todo when no row is left.
 */
function render(todos, shown) {
  const held = document.activeElement;
  const heldRow = held instanceof HTMLElement && list.contains(held) ? held.closest('li') : null;
  const heldAt = Array.prototype.indexOf.call(list.children, heldRow);
  const heldControl = heldRow && held.classList.contains('delete') ? '.delete' : 'input';

  const wanted = new Set(todos.map((todo) => String(todo.id)));
  const kept = new Map();
  for (const item of Array.from(list.children)) {
    if (wanted.has(item.dataset.id)) {
      kept.set(item.dataset.id, item);
    } else {
      item.remove();
    }
  }
  let next = list.firstElementChild;
  for (const todo of todos) {
    const item = kept.get(String(todo.id)) ?? newRow(todo.id);
    fill(item, todo);
    if (item === next) {
      next = next.nextElementSibling;
    } else {
      list.insertBefore(item, next);
    }
  }

  if (heldRow && !heldRow.isConnected) {
    const heir = list.children[Math.min(heldAt, list.children.length - 1)];
    (heir ? heir.querySelector(heldControl) : input).focus();
  }

  if (todos.length === 0) {
    count.textContent = NOTHING[shown];
  } else if (shown === 'all') {
    count.textContent = todos.length === 1 ? '1 todo' : `${todos.length} todos`;
  } else {
    count.textContent = `${todos.length} ${shown}`;
  }
}

async function refresh() {
  const shown = filter;
  const todos = await call('GET', `/todos${QUERY[shown]}`);
  // An answer for a filter that is no longer the pressed one is not shown. The press that
  // changed it has a reading of its own waiting for its turn.
  if (shown === filter) {
    render(todos, shown);
  }
}

/**
 * Does one thing to the list, then reads it again: what is shown is what the API has.
 * Changes take turns. One starts when the one before it, and the reading that follows it,
 * are over, so the list on the page is the list as the last change left it, in whatever
 * order the answers would have come.
 *
 * While any of that is going on the list says so with aria-busy, for a screen reader. The
 * message a change may leave is not inside the list, so it is read out all the same. The
 * document says so too, with data-busy, for whatever wants to know when the page has
 * caught up.
 */
function change(action) {
  // Whatever was said is about something that came before this. It goes now, and not when
  // this change is over: a change that was asked for earlier and is still waiting for its
  // turn must not take away what a later failure says.
  sayNothing();
  return inTurn(async () => {
    try {
      await action();
    } catch (error) {
      sayWhatWentWrong(error);
    }
    try {
      await refresh();
    } catch (error) {
      sayWhatWentWrong(error);
    }
    // The numbers are the list's, so they are read whenever the list may have changed.
    await refreshNumbers();
  });
}

/**
 * Does *action* when everything that was asked for before it is over. Changes to the list
 * and a sign-in share the one queue: a todo that is added while a sign-in is on its way is
 * sent when it is known who is signed in.
 */
function inTurn(action) {
  waiting += 1;
  document.documentElement.dataset.busy = 'true';
  list.setAttribute('aria-busy', 'true');
  const turn = last.then(async () => {
    try {
      await action();
    } finally {
      waiting -= 1;
      if (waiting === 0) {
        delete document.documentElement.dataset.busy;
        list.removeAttribute('aria-busy');
      }
    }
  });
  // A turn only fails for a mistake in the page itself, which is thrown on for the
  // console to show. The turns behind it are still taken.
  last = turn.catch(() => {});
  return turn;
}

async function checkHealth() {
  let api;
  try {
    api = await whereTheApiIs;
  } catch {
    apiOrigin.textContent = 'unknown';
    apiStatus.textContent = 'not asked';
    apiStatus.dataset.state = 'wrong';
    return;
  }
  apiOrigin.textContent = api || location.origin;

  let state = 'wrong';
  let word = 'cannot be reached';
  const waited = patience();
  try {
    const response = await fetch(`${api}/health`, { cache: 'no-store', signal: waited.signal });
    const health = await response.json();
    word = typeof health.status === 'string' ? health.status : `answered ${response.status}`;
    state = response.ok ? 'ok' : 'wrong';
  } catch {
    // Left as it is: not reachable.
  } finally {
    waited.over();
  }
  apiStatus.textContent = word;
  apiStatus.dataset.state = state;
}

form.addEventListener('submit', (event) => {
  event.preventDefault();
  // A second Enter, or a second press of the button, before the first title is known to
  // be kept would add it twice.
  if (adding) {
    return;
  }
  adding = true;
  // Sent as it was typed, empty or not: what a title may be is the API's to say.
  const title = input.value;
  input.focus();
  change(async () => {
    try {
      await call('POST', '/todos', { title });
      // Only what was sent is taken out of the field. Whatever was typed since stays.
      if (input.value === title) {
        input.value = '';
      }
    } finally {
      adding = false;
    }
  });
});

signInForm.addEventListener('submit', (event) => {
  event.preventDefault();
  // A second Enter, or a second press of the button, before the first answer has come
  // would be a second try, and tries are counted.
  if (signingIn) {
    return;
  }
  signingIn = true;
  // Sent as they were typed: what is the right name and password is the API's to say.
  const user = userInput.value;
  const password = passwordInput.value;
  sayNothing(accountMessage);
  inTurn(async () => {
    let answer;
    try {
      answer = await call('POST', '/login', { user, password });
    } catch (error) {
      sayWhatWentWrong(error, accountMessage);
      // For another try, when the keyboard is still here.
      if (signInForm.contains(document.activeElement)) {
        passwordInput.focus();
      }
      return;
    } finally {
      signingIn = false;
      // A password stays in the page no longer than it takes to send it, right or wrong.
      // Whatever was typed since is not what was sent, and stays.
      if (passwordInput.value === password) {
        passwordInput.value = '';
      }
    }
    session = { user: user.trim(), token: answer.token };
    showSession(signOutButton);
    await refreshNumbers();
  });
});

signOutButton.addEventListener('click', () => {
  // At once, and not in its turn: nothing is asked of the API, and whatever is still on its
  // way for whoever was signed in is not shown when it comes.
  session = null;
  showSession(userInput);
  sayNothing(accountMessage);
});

for (const button of filters) {
  button.addEventListener('click', () => {
    filter = button.dataset.filter;
    for (const other of filters) {
      other.setAttribute('aria-pressed', String(other === button));
    }
    change(async () => {});
  });
}

await Promise.all([
  checkHealth(),
  change(async () => {}),
]);
document.documentElement.dataset.ready = 'true';
