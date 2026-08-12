export type SuggestionAction = {
  actionId: string;
  title: string;
  targetValue: number;
  unit: string;
  timeframe: "daily" | "weekly";
  categories: string[];
  sourceTitle: string | null;
  sourceURL: string | null;
  safetyNote: string | null;
};

export const SUGGESTION_ACTIONS: SuggestionAction[] = [
  {
    actionId: "movement.walk_5_daily",
    title: "Take a short walk",
    targetValue: 5,
    unit: "minutes",
    timeframe: "daily",
    categories: ["fitness_health", "stress_load", "peace_wellbeing"],
    sourceTitle: "NIDDK: Staying Active at Any Size",
    sourceURL: "https://www.niddk.nih.gov/health-information/weight-management/staying-active-at-any-size",
    safetyNote: "Choose an activity that feels safe for you. Check with a health professional if you have symptoms or medical concerns.",
  },
  {
    actionId: "movement.breaks_2_daily",
    title: "Take two movement breaks",
    targetValue: 2,
    unit: "times",
    timeframe: "daily",
    categories: ["fitness_health", "career_work", "stress_load"],
    sourceTitle: "CDC: Getting Started With Physical Activity",
    sourceURL: "https://www.cdc.gov/healthy-weight-growth/physical-activity/getting-started.html",
    safetyNote: "Start gently and choose movement that feels safe for you.",
  },
  {
    actionId: "finance.review_spending_5_daily",
    title: "Review today’s spending",
    targetValue: 5,
    unit: "minutes",
    timeframe: "daily",
    categories: ["money_finance"],
    sourceTitle: "CFPB: Track your spending",
    sourceURL: "https://www.consumerfinance.gov/archive/blog/track-your-spending-with-this-easy-tool/",
    safetyNote: "This is a general organization suggestion, not financial advice.",
  },
  {
    actionId: "finance.review_weekly",
    title: "Review one week of spending",
    targetValue: 1,
    unit: "sessions",
    timeframe: "weekly",
    categories: ["money_finance"],
    sourceTitle: "CFPB: Track your spending",
    sourceURL: "https://www.consumerfinance.gov/archive/blog/track-your-spending-with-this-easy-tool/",
    safetyNote: "This is a general organization suggestion, not financial advice.",
  },
  {
    actionId: "routine.next_step_10_daily",
    title: "Do the next small step",
    targetValue: 10,
    unit: "minutes",
    timeframe: "daily",
    categories: ["career_work", "personal_growth", "stress_load"],
    sourceTitle: null,
    sourceURL: null,
    safetyNote: null,
  },
  {
    actionId: "routine.top_task_daily",
    title: "Choose today’s top task",
    targetValue: 1,
    unit: "times",
    timeframe: "daily",
    categories: ["career_work", "personal_growth", "stress_load"],
    sourceTitle: null,
    sourceURL: null,
    safetyNote: null,
  },
];

export function suggestionAction(id: string): SuggestionAction | undefined {
  return SUGGESTION_ACTIONS.find((action) => action.actionId === id);
}
