CREATE TABLE `checkin_categories` (
	`user_id` text NOT NULL,
	`id` text NOT NULL,
	`name` text NOT NULL,
	`normalized_name` text NOT NULL,
	`color` text DEFAULT '#315eec' NOT NULL,
	PRIMARY KEY(`user_id`, `id`)
);
--> statement-breakpoint
CREATE UNIQUE INDEX `checkin_category_name` ON `checkin_categories` (`user_id`,`normalized_name`);--> statement-breakpoint
CREATE TABLE `checkin_devices` (
	`id` text PRIMARY KEY NOT NULL,
	`user_id` text NOT NULL,
	`endpoint` text NOT NULL,
	`active` integer DEFAULT 1 NOT NULL,
	`registered_at` integer NOT NULL,
	`last_push_slot` integer,
	`last_push_kind` text,
	`last_error` text
);
--> statement-breakpoint
CREATE INDEX `checkin_devices_user` ON `checkin_devices` (`user_id`);--> statement-breakpoint
CREATE TABLE `checkin_entries` (
	`user_id` text NOT NULL,
	`end_ms` integer NOT NULL,
	`start_ms` integer NOT NULL,
	`activity` text NOT NULL,
	`category_id` text,
	`answered_at` integer NOT NULL,
	`updated_at` integer NOT NULL,
	`version` integer DEFAULT 1 NOT NULL,
	PRIMARY KEY(`user_id`, `end_ms`)
);
--> statement-breakpoint
CREATE INDEX `checkin_entries_day` ON `checkin_entries` (`user_id`,`start_ms`);--> statement-breakpoint
CREATE TABLE `checkin_reminders` (
	`device_id` text NOT NULL,
	`end_ms` integer NOT NULL,
	`attempted_at` integer NOT NULL,
	`accepted_at` integer,
	`status` text DEFAULT 'claimed' NOT NULL,
	PRIMARY KEY(`device_id`, `end_ms`)
);
--> statement-breakpoint
CREATE TABLE `checkin_runtime` (
	`key` text PRIMARY KEY NOT NULL,
	`value` text NOT NULL
);
--> statement-breakpoint
CREATE TABLE `checkin_settings` (
	`user_id` text PRIMARY KEY NOT NULL,
	`timezone` text DEFAULT 'Europe/Berlin' NOT NULL,
	`start_minute` integer DEFAULT 420 NOT NULL,
	`end_minute` integer DEFAULT 1320 NOT NULL,
	`enabled` integer DEFAULT 1 NOT NULL,
	`time_format` text DEFAULT '12' NOT NULL,
	`version` integer DEFAULT 1 NOT NULL
);
