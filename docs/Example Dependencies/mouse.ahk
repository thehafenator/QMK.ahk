class mouse{
    static move(direction := "")
{
    key := key := StrReplace(A_ThisHotkey, " up", "")
    directions := Map("h", [-1, 0], "j", [0, 1], "k", [0, -1], "l", [1, 0]) ; works with hjkl, change as desired (see example below)
    ; directions := Map("left", [-1, 0], "down", [0, 1], "up", [0, -1], "right", [1, 0]) ; comment this line to instead call as "mouse.move("up")"
    dir := directions[key]
    startTime := A_TickCount
    while GetKeyState(key, "P") {
        elapsed := A_TickCount - startTime

        ; ; Progressive speed scaling, change as needed
        if (elapsed < 10) {
            speed := 10
        } else if (elapsed < 50) {  ; 50 + 150
            speed := 20
            ; }
            ; else if (elapsed < 40) {  ; 200 + 100
            ;     speed := 40
            ; } else if (elapsed < 60) {  ; 300 + 50
            ;     speed := 80
        } else {
            speed := 50
        }
        MouseMove(dir[1] * speed, dir[2] * speed, 0, "R")
        Sleep(10)
    }
}

static click(key := ""){
    Send("{LButton down}")
    KeyWait(key)
    Send("{LButton up}")
}
}