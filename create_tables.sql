CREATE TABLE IF NOT EXISTS "activity" (
    "id" INTEGER PRIMARY KEY NOT NULL,
    "resource_state" INTEGER,
    "external_id" TEXT,
    "athlete_id" INTEGER,
    "name" TEXT,
    "description" TEXT,
    "distance" REAL,
    "moving_time" INTEGER,
    "elapsed_time" INTEGER,
    "total_elevation_gain" REAL,
    "type" TEXT,
    "start_date" INTEGER,
    "trainer" INTEGER,
    "commute" INTEGER,
    "manual" INTEGER,
    "private" INTEGER,
    "flagged" INTEGER
);
CREATE TABLE IF NOT EXISTS "best_effort" (
    "distance" INTEGER NOT NULL,
    "moving_time" INTEGER NOT NULL,
    "elapsed_time" INTEGER NOT NULL,
    "activity_id" INTEGER NOT NULL,
    PRIMARY KEY ("distance", "activity_id")
);
