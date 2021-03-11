@echo off
echo .
echo v1.7
::1.1 Добавлена остановка службы, на всякий случай
::1.2 Добавлена проверка системных баз
::1.3 Исправлена процедура поиска папок хранения БД
::1.4 Корректное создание пользователя srvcEASOPSupdate
::1.5 Исправлена процедура поиска папок хранения БД вроде окончательно
::1.6 Включение пользователя "NT AUTHORITY\система" в роль sysadmin
::1.7 Добавлен поиск по всем папкам с базами(которые можно вытащить из реестра)
::    - Удалена проверка на пустоту алиаса
::1.8 включение xp_cmdshell

echo .
setlocal ENABLEDELAYEDEXPANSION ENABLEEXTENSIONS

@rem Определение переменных.
set /p saPass="ВВедите пароль SA: "
:: ДЛЯ ТЕСТА set saPass="Pd"

:: нужно ли задавать пароль pmuser вручную?
@rem set /p pmPass="Введите пароль pmuser: "

set cName=%computername%
echo Имя компьютера: %cName% > rebuild.log 

set uName=%username%
echo Имя пользователя: %uName% >> rebuild.log 

set uDomain=%UserDomain%
echo Домен компьютера: %uDomain% >> rebuild.log 

@rem Rebuild system databases
@rem в параметре /SQLSYSADMINACCOUNTS либо домен, либо имя компа (uDomain либо cName)
net stop MSSQLSERVER
echo Служба MSSQLSERVER остановлена >> rebuild.log

"c:\Program Files\Microsoft SQL Server\110\Setup Bootstrap\SQLServer2012\setup.exe" /ACTION=REBUILDDATABASE /QUIET /INSTANCENAME=MSSQLSERVER /SQLSYSADMINACCOUNTS=%uDomain%\%uName% /SAPWD=%saPass% 

net start MSSQLSERVER
echo Системные базы успешно созданы
echo Системные базы успешно созданы >> rebuild.log
echo Служба MSSQLSERVER запущена >> rebuild.log
::*************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************************
echo Начало присоединения баз
echo Начало присоединения баз >> rebuild.log
@rem Attach databases
@rem AddrExt1, AddrExt1Aux, AddrExt2, AddrExt2Aux, BankOfMoscow, BankOfMoscowPension, BiletOnLine, DBindex, ESPP, FSG_x_xx_x, ITSK, LetoBank, LXGoods, MarketPlace, OPC, Plugin_StoLoto, Plugin_UFS, pmowner, PostBox, PostPay, Postpayspb

@rem Определение пути в базам данных

@rem Проверяем сначала пользовательские настройки хранения баз ЕАС ОПС
@rem находятся в HKLM\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQLServer      DefaultData            
@rem ошибка при отсутствии раздела глушится конструкцией '2>nul 1>&2'

Reg Query "HKLM\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQLServer" /v "DefaultData" 2>nul 1>&2 && echo. || goto forward 

@rem если ключ существует выполняем поиск папки в нем и идем по скрипту, если нет - перескакиваем на метку :forward

for /f "tokens=2* delims= " %%a in ('Reg Query "HKLM\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL11.MSSQLSERVER\MSSQLServer" /v "DefaultData"') do set dbFolder=%%b
echo Найдена пользовательская папка хранения БД %dbFolder%
echo Найдена пользовательская папка хранения БД %dbFolder% >> rebuild.log

@rem Передаем найденную папку в процедуру поиска в ней баз данных
call :dbSearch %dbFolder%


@rem вытаскиваем из ключа HKLM\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL11.MSSQLSERVER\Setup     SQLDataRoot   путь, где по умолчанию хранятся БД
:forward
echo Пользовательские настройки хранения проверены или не найдены, поиск в путях по умолчанию :
for /f "tokens=2* delims= " %%a in ('Reg Query "HKLM\SOFTWARE\Microsoft\Microsoft SQL Server\MSSQL11.MSSQLSERVER\Setup" /v "SQLDataRoot"') do set dbFolder=%%b\DATA
echo Найдена папка хранения БД %dbFolder%
echo Найден путь хранения баз данных "%dbFolder%"  >> rebuild.log
@rem добавляем \DATA, т.к. при стандартных настройках в ключе SQLDataRoot его не хватает, а ключ DefaultData вообще не создается
@rem к тому же присутствует некий файл mssqlsystemresource.mdf он лежит в \Binn\ и не должен учавствовать в восстановлении
@rem Передаем найденную папку в процедуру поиска в ней баз данных
call :dbSearch %dbFolder%
@rem После присоединения всех баз перескакиваем на процедуру работы с пользователями
goto :LoginMaker

:dbSearch
if %1=="" goto :LoginMaker
@rem Ищем базы данных по полученному пути
for /f "tokens=* delims=" %%i in ('where /r "%1" *.mdf') do call :checksys "%%i" %%~ni 
@rem передаем в цикл 2 переменные : полный путь файла(D:\DATA\dbase.mdf) для указания в скрипте места расположения файла БД, и только имя файла (dbase) для использования его как алиаса БД
exit /b

:CheckSYS
@rem Проверяем насистемные БД, чтобы по второму разу их не добавлять
set newDb=%1
set dbAlias=%2
if not %dbAlias%==master (
 @if not %dbAlias%==model (
   @if not %dbAlias%==tempdb (
     @if not %dbAlias%==MSDBData (
           call :ScriptMaker %newDb% %dbAlias%
           ) else echo.системные базы пропущены )))


exit /b

:ScriptMaker
@rem Создаем и выполняем скрипт присоединения БД к серверу
set newDb=%1
set dbAlias=%2
echo USE [master] > temp.sql
echo выполняется присоединение базы %newDb%
echo GO >> temp.sql
echo if not exists (select 1 from sys.databases where name = '%dbAlias%') >> temp.sql
echo CREATE DATABASE [%dbAlias%] ON ( FILENAME = %newDb% ) FOR ATTACH >> temp.sql
echo GO >> temp.sql
@rem выполнение скрипта temp.sql
sqlcmd -S localhost -i temp.sql -U sa -P %saPass% 1>nul
@rem удаление скрипта temp.sql
DEL .\temp.sql /Q
echo БД %dbAlias% присоединена к серверу >> rebuild.log

exit /b


@rem ***********************************************************************************************************************************************************
@rem Create accounts
@rem pmuser, srvcEASOPSupdate
@rem пользователь имя_компьютера\имя_пользователя создается при создании ситемных баз. 
@rem easops_operator создается отдельной утилитой


:LoginMaker
echo Создаем пользователя pmuser
@rem удаление старого пользователя pmuser из базы pmowner
echo USE [pmowner] > temp.sql
echo GO >> temp.sql >> temp.sql
echo DROP USER [pmuser] >> temp.sql
echo GO >> temp.sql
@rem выполнение скрипта temp.sql
sqlcmd -S localhost -i temp.sql -U sa -P %saPass% 1>nul
echo Логин pmuser удален >> rebuild.log
@rem удаление скрипта temp.sql
DEL .\temp.sql /Q



@rem создаем скрипт для pmuser
echo USE [master] > temp.sql
echo GO >> temp.sql
echo CREATE LOGIN [pmuser] WITH PASSWORD=N'PF1234', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF >> temp.sql
echo GO >> temp.sql
echo USE [pmowner] >> temp.sql
echo GO >> temp.sql
echo CREATE USER [pmuser] FOR LOGIN [pmuser] >> temp.sql
echo GO >> temp.sql
echo ALTER USER [pmuser] WITH DEFAULT_SCHEMA=[dbo] >> temp.sql
echo GO >> temp.sql
echo ALTER ROLE [db_owner] ADD MEMBER [pmuser] >> temp.sql
echo GO >> temp.sql
@rem выполнение скрипта temp.sql
sqlcmd -S localhost -i temp.sql -U sa -P %saPass% 1>nul
echo Логин pmuser создан
echo Логин pmuser создан >> rebuild.log
@rem удаление скрипта temp.sql
DEL .\temp.sql /Q

@rem создаем скрипт для srvcEASOPSupdate
echo USE [master] > temp.sql
echo GO >> temp.sql
echo CREATE LOGIN [%cName%\srvcEASOPSupdate] FROM WINDOWS WITH DEFAULT_DATABASE=[master] >> temp.sql
echo GO >> temp.sql
echo ALTER SERVER ROLE [sysadmin] ADD MEMBER [%cName%\srvcEASOPSupdate] >> temp.sql
echo GO >> temp.sql
@rem выполнение скрипта temp.sql
sqlcmd -S localhost -i temp.sql -U sa -P %saPass% 1>nul
echo Логин srvcEASOPSupdate создан
echo Логин srvcEASOPSupdate создан >> rebuild.log
@rem удаление скрипта temp.sql
DEL .\temp.sql /Q

@rem Добавляем роль sysadmin к имени входа "NT AUTHORITY\система", шедулер без этого не работает
echo USE [master] > temp.sql
echo GO >> temp.sql
echo declare @sidNT nchar(20), @query varchar(150); >> temp.sql
echo select @sidNT = name from sys.syslogins where loginname like 'NT AUTHORITY%%'; >> temp.sql
:: выше удвоение %% для корректной записи в скрипт(cmd не обрабатывает %,ждет переменную)
echo set @query = 'ALTER SERVER ROLE [sysadmin] ADD MEMBER [' + @sidNT+ ']'; >> temp.sql
echo exec(@query); >> temp.sql
echo GO >> temp.sql
@rem выполнение скрипта temp.sql
sqlcmd -S localhost -i temp.sql -U sa -P %saPass% 1>nul
echo Права сисадмина NT AUTHORITY\система выданы
echo Права сисадмина NT AUTHORITY\система выданы >> rebuild.log
@rem удаление скрипта temp.sql
DEL .\temp.sql /Q

@rem Включение xp_cmdshell
echo USE [master] > temp.sql
echo GO >> temp.sql
echo EXEC sp_configure 'show advanced options', 1; >> temp.sql
echo GO >> temp.sql
echo RECONFIGURE; >> temp.sql
echo GO >> temp.sql
echo EXEC sp_configure 'xp_cmdshell', 1; >> temp.sql
echo GO >> temp.sql
echo RECONFIGURE; >> temp.sql
echo GO >> temp.sql
@rem выполнение скрипта temp.sql
sqlcmd -S localhost -i temp.sql -U sa -P %saPass% 1>nul
echo xp_cmdshell включена
echo xp_cmdshell включена >> rebuild.log
@rem удаление скрипта temp.sql
DEL .\temp.sql /Q

echo .....
echo ВНИМАНИЕ!!!
echo Логин easops_operator создается отдельной утилитой! 

endlocal

TIMEOUT 3 /NOBREAK
