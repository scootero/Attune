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
    actionId: "finance.label_three_daily",
    title: "Label three recent purchases",
    targetValue: 1,
    unit: "sessions",
    timeframe: "daily",
    categories: ["money_finance"],
    sourceTitle: "CFPB: Track your spending",
    sourceURL: "https://www.consumerfinance.gov/archive/blog/track-your-spending-with-this-easy-tool/",
    safetyNote: "This is a general awareness exercise, not financial advice.",
  },
  {
    actionId: "learning.teach_one_daily",
    title: "Teach one idea from memory",
    targetValue: 1,
    unit: "times",
    timeframe: "daily",
    categories: ["personal_growth"],
    sourceTitle: "Roediger and Karpicke: Test-enhanced learning",
    sourceURL: "https://doi.org/10.1126/science.1127335",
    safetyNote: null,
  },
  {
    actionId: "learning.recall_three_weekly",
    title: "Recall three ideas without notes",
    targetValue: 1,
    unit: "sessions",
    timeframe: "weekly",
    categories: ["personal_growth"],
    sourceTitle: "Roediger and Karpicke: Test-enhanced learning",
    sourceURL: "https://doi.org/10.1126/science.1127335",
    safetyNote: null,
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
    actionId: "routine.name_visible_step_daily",
    title: "Name the next visible step",
    targetValue: 1,
    unit: "times",
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
  {
    actionId: "connection.specific_checkin_daily",
    title: "Send one thoughtful check-in",
    targetValue: 1,
    unit: "times",
    timeframe: "daily",
    categories: ["relationships_social"],
    sourceTitle: null,
    sourceURL: null,
    safetyNote: "Choose a relationship and message that feel safe and appropriate to you.",
  },
];

export function suggestionAction(id: string): SuggestionAction | undefined {
  return SUGGESTION_ACTIONS.find((action) => action.actionId === id);
}
