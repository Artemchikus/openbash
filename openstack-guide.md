Для создания одноузлового кластера надо:

1. Открыть Linux
2. dnf -y install qemu-kvm libvirt virt-install - установить пакеты для KVM
3. git clone https://github.com/artemchicus/openbash - склонировать репозиторий
4. cd testInstance - перейти в папку с фархивом для создания тестового узла
5. Разархивировать архив
6. sudo cp \*qcow2 /mnt/kvm/disk - перенести файлы дсиков в нужную папку
7. sudo virsh net-define default.xml - создать сеть для узла
8. sudo net-autostart default - настроить автозапуск сети
9. sudo virsh define cont9.xml - создать определеие ВМ
10. sudo virsh start cont9 - запустить ВМ
11. sudo virsh console cont9 - закрепить консоль ВМ за терминалом
12. export ИМЯ_ПЕРЕМЕННОЙ=ЗНАЧЕНИЕ - адать ENV переменные для конфигруации (опционально)
13. ./configure.sh - запустить скрипт конфигурации сервисов Openstack
14. source keystonerc_adm - запсутить скрипт для работы с Openstack через командную строку
15. Ctrl + [] - открепить консоль
16. sudo virsh shutdown cont9 - выключить ВМ
