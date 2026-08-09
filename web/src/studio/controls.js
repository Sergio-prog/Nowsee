import { PALETTES } from "../palettes.js";
import { GROUPS } from "./schema.js";

const ROW = "flex flex-col gap-[7px]";
const HEAD = "flex items-baseline justify-between gap-3";
const NAME = "font-mono text-[10.5px] tracking-[0.11em] uppercase text-dim";
const VALUE = "font-mono text-[11px] tabular-nums text-ink/85";
const SEGMENT =
  "flex-1 cursor-pointer rounded-[5px] px-2 py-[5px] font-mono text-[11px] text-dim transition-colors hover:text-ink aria-pressed:bg-[var(--accent)] aria-pressed:text-[var(--accent-ink)]";
const SWATCH =
  "h-[17px] w-full cursor-pointer rounded-[3px] border border-white/12 transition-transform hover:-translate-y-px aria-pressed:border-transparent aria-pressed:shadow-[0_0_0_1px_var(--color-void),0_0_0_2.5px_var(--accent)]";

function el(tag, className, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text != null) node.textContent = text;
  return node;
}

function rangeRow(control, state, onChange) {
  const row = el("div", ROW);
  const head = el("div", HEAD);
  const name = el("span", NAME, control.label);
  const value = el("span", VALUE);
  const input = el("input", "knob");
  input.type = "range";
  input.min = control.min;
  input.max = control.max;
  input.step = control.step;
  input.setAttribute("aria-label", control.label);

  const sync = () => {
    const current = Number(state[control.key]);
    input.value = String(current);
    value.textContent = control.format ? control.format(current) : String(current);
    const fill = ((current - control.min) / (control.max - control.min)) * 100;
    input.style.setProperty("--fill", `${fill}%`);
  };

  input.addEventListener("input", () => {
    onChange(control.key, Number(input.value));
    sync();
  });

  head.append(name, value);
  row.append(head, input);
  return { row, sync };
}

function toggleRow(control, state, onChange) {
  const row = el("div", "flex items-center justify-between gap-3 py-[3px]");
  const name = el("span", NAME, control.label);
  const button = el(
    "button",
    "relative h-[17px] w-[30px] shrink-0 cursor-pointer rounded-full bg-white/12 transition-colors aria-checked:bg-[var(--accent)]",
  );
  button.type = "button";
  button.setAttribute("role", "switch");
  const knob = el(
    "span",
    "absolute top-[2.5px] left-[2.5px] h-3 w-3 rounded-full bg-ink transition-transform",
  );
  button.append(knob);

  const sync = () => {
    const on = Boolean(state[control.key]);
    button.setAttribute("aria-checked", String(on));
    knob.style.transform = on ? "translateX(13px)" : "translateX(0)";
  };

  button.addEventListener("click", () => {
    onChange(control.key, !state[control.key]);
    sync();
  });

  row.append(name, button);
  return { row, sync };
}

function selectRow(control, state, onChange) {
  const row = el("div", ROW);
  const name = el("span", NAME, control.label);
  const group = el("div", "flex gap-[3px] rounded-[7px] border border-hairline bg-white/3 p-[3px]");
  group.setAttribute("role", "group");
  group.setAttribute("aria-label", control.label);

  const buttons = control.options.map((option) => {
    const button = el("button", SEGMENT, option.label);
    button.type = "button";
    button.addEventListener("click", () => {
      onChange(control.key, option.value);
      sync();
    });
    group.append(button);
    return { button, option };
  });

  const sync = () => {
    buttons.forEach(({ button, option }) =>
      button.setAttribute("aria-pressed", String(state[control.key] === option.value)),
    );
  };

  row.append(name, group);
  return { row, sync };
}

function colorRow(control, state, onChange) {
  const row = el("div", "flex items-center justify-between gap-3 py-[3px]");
  const name = el("span", NAME, control.label);
  const wrap = el("div", "flex items-center gap-2");
  const hex = el("span", "font-mono text-[11px] tabular-nums text-dim");
  const input = el(
    "input",
    "h-[19px] w-[30px] cursor-pointer rounded-[3px] border border-white/15 bg-transparent p-0",
  );
  input.type = "color";
  input.setAttribute("aria-label", control.label);

  const sync = () => {
    input.value = state[control.key];
    hex.textContent = String(state[control.key]).toUpperCase();
  };

  input.addEventListener("input", () => {
    onChange(control.key, input.value);
    sync();
  });

  wrap.append(hex, input);
  row.append(name, wrap);
  return { row, sync };
}

function paletteRow(control, state, onChange) {
  const row = el("div", ROW);
  const name = el("span", NAME, control.label);
  const grid = el("div", "grid grid-cols-5 gap-[5px]");
  grid.setAttribute("role", "group");
  grid.setAttribute("aria-label", control.label);

  const entries = [...Object.entries(PALETTES), ["custom", null]];
  const buttons = entries.map(([id, stops]) => {
    const button = el("button", SWATCH);
    button.type = "button";
    button.title = id === "custom" ? "Custom" : id[0].toUpperCase() + id.slice(1);
    button.setAttribute("aria-label", button.title);
    if (stops) button.style.background = `linear-gradient(90deg, ${stops.join(",")})`;
    button.addEventListener("click", () => {
      onChange(control.key, id);
      sync();
    });
    grid.append(button);
    return { button, id, stops };
  });

  const sync = () => {
    buttons.forEach(({ button, id, stops }) => {
      button.setAttribute("aria-pressed", String(state[control.key] === id));
      if (!stops) {
        button.style.background = `linear-gradient(90deg, ${state.low}, ${state.mid}, ${state.high})`;
      }
    });
  };

  row.append(name, grid);
  return { row, sync };
}

const BUILDERS = {
  range: rangeRow,
  toggle: toggleRow,
  select: selectRow,
  color: colorRow,
  palette: paletteRow,
};

export function createControls(root, state, onChange) {
  const rows = [];
  const sections = [];

  GROUPS.forEach((group) => {
    const section = el("section", "border-t border-hairline px-4 py-4");
    const title = el("h3", "label-mono mb-3 text-dimmer", group.title);
    const body = el("div", "flex flex-col gap-[13px]");
    section.append(title, body);

    group.controls.forEach((control) => {
      const built = BUILDERS[control.type](control, state, onChange);
      body.append(built.row);
      rows.push({ ...built, control });
    });

    root.append(section);
    sections.push({ section, group });
  });

  function refresh() {
    sections.forEach(({ section, group }) => {
      section.hidden = Boolean(group.when && !group.when(state));
    });
    rows.forEach(({ row, sync, control }) => {
      row.hidden = Boolean(control.when && !control.when(state));
      sync();
    });
  }

  refresh();
  return { refresh };
}
