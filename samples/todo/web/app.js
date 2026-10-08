// The page's whole behaviour, as one module. It asks its own server where the API is,
// and from then on talks to that origin: the one it came from, or another that allows it.
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

const QUERY = { all: '', open: '?done=false', done: '?done=true' };
const NOTHING = { all: 'Nothing to do yet.', open: 'Nothing open.', done: 'Nothing done yet.' };

let api = '';
let filter = 'all';

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
class Unreachable extends Error {}

async function call(method, path, body) {
  const init = { method, headers: {} };
  if (body !== undefined) {
    init.headers['Content-Type'] = 'application/json';
    init.body = JSON.stringify(body);
  }

  let response;
  try {
    response = await fetch(api + path, init);
  } catch {
    // A failed connection and an answer the browser withholds from this origin look the
    // same from here, on purpose: a page is not told which.
    throw new Unreachable();
  }

  if (response.ok) {
    return response.status === 204 ? null : response.json();
  }
  throw await refusalOf(response);
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

function say(lines, wrong) {
  message.classList.toggle('wrong', wrong);
  message.replaceChildren(...lines);
}

function sayNothing() {
  say([], false);
}

function sayWhatWentWrong(error) {
  if (error instanceof Refusal) {
    const lines = [line(error.message)];
    for (const [field, problems] of Object.entries(error.errors)) {
      const said = Array.isArray(problems) ? problems.join(', ') : String(problems);
      lines.push(line(`${field}: ${said}`, 'field'));
    }
    if (error.requestId) {
      lines.push(line(`Request ${error.requestId}`, 'request'));
    }
    say(lines, true);
  } else if (error instanceof Unreachable) {
    say([
      line(`The API at ${api || location.origin} cannot be reached from this page.`),
      line(`If it is running, it may not allow pages from ${location.origin}.`),
    ], true);
  } else {
    say([line('Something went wrong in the page itself.')], true);
    throw error;
  }
}

function render(todos) {
  list.replaceChildren(...todos.map((todo) => {
    const item = row.content.firstElementChild.cloneNode(true);
    const box = item.querySelector('input');
    item.classList.toggle('done', todo.done);
    item.querySelector('.title').textContent = todo.title;
    box.checked = todo.done;
    box.addEventListener('change', () => change(() => call('PUT', `/todos/${todo.id}`, { done: box.checked })));
    const remove = item.querySelector('.delete');
    // Said aloud, "Delete" alone does not say which.
    remove.setAttribute('aria-label', `Delete: ${todo.title}`);
    remove.addEventListener('click', () => change(() => call('DELETE', `/todos/${todo.id}`)));
    return item;
  }));

  if (todos.length === 0) {
    count.textContent = NOTHING[filter];
  } else if (filter === 'all') {
    count.textContent = todos.length === 1 ? '1 todo' : `${todos.length} todos`;
  } else {
    count.textContent = `${todos.length} ${filter}`;
  }
}

async function refresh() {
  render(await call('GET', `/todos${QUERY[filter]}`));
}

/** Does one thing to the list, then reads it again: what is shown is always what the API has. */
async function change(action) {
  try {
    await action();
    sayNothing();
  } catch (error) {
    sayWhatWentWrong(error);
  }
  try {
    await refresh();
  } catch (error) {
    sayWhatWentWrong(error);
  }
}

async function checkHealth() {
  let state = 'wrong';
  let word = 'cannot be reached';
  try {
    const response = await fetch(`${api}/health`, { cache: 'no-store' });
    const health = await response.json();
    word = typeof health.status === 'string' ? health.status : `answered ${response.status}`;
    state = response.ok ? 'ok' : 'wrong';
  } catch {
    // Left as it is: not reachable.
  }
  apiStatus.textContent = word;
  apiStatus.dataset.state = state;
}

async function whereTheApiIs() {
  try {
    const response = await fetch('config.json', { cache: 'no-store' });
    const config = await response.json();
    return typeof config.api === 'string' ? config.api : '';
  } catch {
    // A server that says nothing about it is its own API.
    return '';
  }
}

form.addEventListener('submit', async (event) => {
  event.preventDefault();
  // Sent as it was typed, empty or not: what a title may be is the API's to say.
  const title = input.value;
  input.focus();
  await change(async () => {
    await call('POST', '/todos', { title });
    input.value = '';
  });
});

for (const button of filters) {
  button.addEventListener('click', async () => {
    filter = button.dataset.filter;
    for (const other of filters) {
      other.setAttribute('aria-pressed', String(other === button));
    }
    await change(async () => {});
  });
}

api = await whereTheApiIs();
apiOrigin.textContent = api || location.origin;
await Promise.all([
  checkHealth(),
  refresh().catch(sayWhatWentWrong),
]);
document.documentElement.dataset.ready = 'true';
