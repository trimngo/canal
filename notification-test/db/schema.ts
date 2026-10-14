import {integer,sqliteTable,text,primaryKey,uniqueIndex,index} from 'drizzle-orm/sqlite-core';
export const settings=sqliteTable('checkin_settings',{
 userId:text('user_id').primaryKey(),timezone:text('timezone').notNull().default('Europe/Berlin'),startMinute:integer('start_minute').notNull().default(420),endMinute:integer('end_minute').notNull().default(1320),enabled:integer('enabled').notNull().default(1),timeFormat:text('time_format').notNull().default('12'),version:integer('version').notNull().default(1)
});
export const categories=sqliteTable('checkin_categories',{
 userId:text('user_id').notNull(),id:text('id').notNull(),name:text('name').notNull(),normalizedName:text('normalized_name').notNull(),color:text('color').notNull().default('#315eec')
},t=>[primaryKey({columns:[t.userId,t.id]}),uniqueIndex('checkin_category_name').on(t.userId,t.normalizedName)]);
export const entries=sqliteTable('checkin_entries',{
 userId:text('user_id').notNull(),endMs:integer('end_ms').notNull(),startMs:integer('start_ms').notNull(),activity:text('activity').notNull(),categoryId:text('category_id'),answeredAt:integer('answered_at').notNull(),updatedAt:integer('updated_at').notNull(),version:integer('version').notNull().default(1)
},t=>[primaryKey({columns:[t.userId,t.endMs]}),index('checkin_entries_day').on(t.userId,t.startMs)]);
export const devices=sqliteTable('checkin_devices',{
 id:text('id').primaryKey(),userId:text('user_id').notNull(),endpoint:text('endpoint').notNull(),active:integer('active').notNull().default(1),registeredAt:integer('registered_at').notNull(),lastPushSlot:integer('last_push_slot'),lastPushKind:text('last_push_kind'),lastError:text('last_error')
},t=>[index('checkin_devices_user').on(t.userId)]);
export const reminders=sqliteTable('checkin_reminders',{
 deviceId:text('device_id').notNull(),endMs:integer('end_ms').notNull(),attemptedAt:integer('attempted_at').notNull(),acceptedAt:integer('accepted_at'),status:text('status').notNull().default('claimed')
},t=>[primaryKey({columns:[t.deviceId,t.endMs]})]);
export const runtime=sqliteTable('checkin_runtime',{key:text('key').primaryKey(),value:text('value').notNull()});
