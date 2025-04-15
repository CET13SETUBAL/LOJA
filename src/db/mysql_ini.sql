
#Administrador total de todas as bases dados
#Sys Admin e Database Admin

CREATE USER IF NOT EXISTS 'adminis'@'%' IDENTIFIED BY 'ZZtopes!23';
GRANT ALL PRIVILEGES ON *.* TO 'adminis'@'%' WITH GRANT OPTION;
FLUSH PRIVILEGES;