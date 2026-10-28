import calendar from "./templates/calendar.json";
import chores from "./templates/chores.json";
import focus from "./templates/focus.json";
import habitTracker from "./templates/habitTracker.json";
import notes from "./templates/notes.json";
import phoneToolkit from "./templates/phoneToolkit.json";
import photoJournal from "./templates/photoJournal.json";
import planner from "./templates/planner.json";
import projectHub from "./templates/projectHub.json";
import reading from "./templates/reading.json";
import reminders from "./templates/reminders.json";
import volunteer from "./templates/volunteer.json";
import { decodeAppSpec } from "../spec/decode";

const samples = [
  [
    "planner",
    planner,
    "Plan a day with tasks, progress, and dedicated record pages.",
  ],
  [
    "projectHub",
    projectHub,
    "Move work through a board and coordinate assignments.",
  ],
  [
    "volunteer",
    volunteer,
    "Try capacity limits, claims, and releases with sample people.",
  ],
  [
    "reading",
    reading,
    "Keep a reading journal and explore complete summary counts.",
  ],
  [
    "habitTracker",
    habitTracker,
    "Track a habit with typed forms and progress views.",
  ],
  ["calendar", calendar, "Explore dates, a calendar, and record navigation."],
  ["notes", notes, "Collect notes using the same shared mini-app engine."],
  ["chores", chores, "Organize shared work and declared workflow actions."],
  [
    "photoJournal",
    photoJournal,
    "Browse synthetic private-image examples in an isolated preview.",
  ],
  [
    "reminders",
    reminders,
    "Explore sample reminder states without scheduling anything.",
  ],
  ["focus", focus, "Try a clock and focus timer with local preview state."],
  [
    "phoneToolkit",
    phoneToolkit,
    "Explore simulated device readings and controls.",
  ],
] as const;

/** Public canonical definitions; previews receive no authenticated host dependencies. */
export const fullTemplates = samples.map(([id, source, caption]) => ({
  id,
  caption,
  spec: decodeAppSpec(source),
}));
