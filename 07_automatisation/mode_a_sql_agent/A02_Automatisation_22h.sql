USE msdb;
EXEC dbo.sp_update_schedule @name = N'TuniShop - Chaque nuit',
     @enabled = 1,
     @active_start_time = 220000;   -- 22:00:00

SELECT s.name, s.enabled, s.active_start_time, js.next_run_date, js.next_run_time
FROM dbo.sysschedules AS s
JOIN dbo.sysjobschedules AS js ON js.schedule_id = s.schedule_id
WHERE s.name = N'TuniShop - Chaque nuit';