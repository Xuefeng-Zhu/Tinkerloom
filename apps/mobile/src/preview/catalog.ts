import { PreviewTemplate } from "./model";

export const previewTemplates: PreviewTemplate[] = [
  {
    id: "planner",
    caption: "Bring dates and small estimates together in an agenda.",
    definition: {
      title: "A little plan",
      description: "Give each next step a date, or leave space for later.",
      primaryFieldId: "title",
      view: { kind: "agenda", dateFieldId: "day" },
      fields: [
        { id: "title", label: "Plan", kind: "text", required: true },
        { id: "day", label: "Planned date", kind: "date" },
        { id: "minutes", label: "Minutes", kind: "number" },
        { id: "done", label: "Completed", kind: "boolean" },
        { id: "notes", label: "A few details", kind: "longText" },
      ],
    },
    samples: [
      {
        title: "Plan the community potluck",
        day: "2026-11-03",
        minutes: 30,
        done: false,
        notes: "Ask everyone for one dish they love.",
      },
      {
        title: "Take a screen-free lunch",
        day: "2026-11-02",
        minutes: 0,
        done: false,
        notes: "A little time outdoors.",
      },
      {
        title: "Explore a new walking route",
        day: "",
        minutes: "",
        done: false,
        notes: "Keep this one for a sunny afternoon.",
      },
    ],
  },
  {
    id: "notes",
    caption: "A quiet place for ideas worth keeping.",
    definition: {
      title: "Little notes",
      description:
        "Collect your ideas, observations, and useful little things.",
      primaryFieldId: "title",
      fields: [
        { id: "title", label: "Title", kind: "text", required: true },
        { id: "body", label: "Note", kind: "longText" },
        {
          id: "category",
          label: "Collection",
          kind: "choice",
          options: ["Ideas", "Everyday", "To explore"],
        },
      ],
    },
    samples: [
      {
        title: "A tiny herb garden",
        body: "Basil by the kitchen window. Mint in its own pot.",
        category: "Ideas",
      },
      {
        title: "Saturday at the market",
        body: "Find the ceramics stall near the flowers.",
        category: "Everyday",
      },
      {
        title: "A book swap with friends",
        body: "Bring one book you loved and a small note inside.",
        category: "To explore",
      },
    ],
  },
  {
    id: "tasks",
    caption: "Turn a busy day into a few doable steps.",
    definition: {
      title: "A little progress",
      description: "Keep the next step in sight, and enjoy checking it off.",
      primaryFieldId: "title",
      fields: [
        { id: "title", label: "Task", kind: "text", required: true },
        { id: "done", label: "Completed", kind: "boolean" },
        {
          id: "priority",
          label: "Priority",
          kind: "choice",
          options: ["Whenever", "Soon", "Today"],
        },
        { id: "detail", label: "A few details", kind: "longText" },
      ],
    },
    samples: [
      {
        title: "Plan a walk with Maya",
        done: false,
        priority: "Today",
        detail: "Try the trail along the river.",
      },
      {
        title: "Make room for a new idea",
        done: false,
        priority: "Soon",
        detail: "Clear a little space on the desk.",
      },
      {
        title: "Water the plants",
        done: true,
        priority: "Whenever",
        detail: "",
      },
    ],
  },
  {
    id: "reading",
    caption: "Give your next good read a place to land.",
    definition: {
      title: "The reading nook",
      description:
        "A small shelf for books, discoveries, and favorite passages.",
      primaryFieldId: "title",
      fields: [
        { id: "title", label: "Book", kind: "text", required: true },
        { id: "author", label: "Author", kind: "text" },
        {
          id: "status",
          label: "Reading status",
          kind: "choice",
          options: ["Want to read", "Reading", "Finished"],
        },
        { id: "notes", label: "What stayed with you?", kind: "longText" },
      ],
    },
    samples: [
      {
        title: "The Secret Garden",
        author: "Frances Hodgson Burnett",
        status: "Reading",
        notes: "A place slowly coming back to life.",
      },
      {
        title: "A Room of One’s Own",
        author: "Virginia Woolf",
        status: "Want to read",
        notes: "",
      },
      {
        title: "The Wind in the Willows",
        author: "Kenneth Grahame",
        status: "Finished",
        notes: "Save this one for a rainy afternoon.",
      },
    ],
  },
];
