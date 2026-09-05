class Scroll {
    ; Configuration
    static sensitivity := 1.0 ; this can be changed. Defalt 1.0
    static smoothing := 8 ; this can be changed. Default 8
    static updateRate := 20 ; this can be changed. Default 20

    ; State
    static velocity := 0
    static isScrolling := false
    static timer := 0

    static Up() {
        Scroll.velocity += Scroll.sensitivity
        Scroll.StartScrolling()
    }
    
    static Down() {
        Scroll.velocity -= Scroll.sensitivity
        Scroll.StartScrolling()
    }

    static StartScrolling() {
        if (!Scroll.isScrolling) {
            Scroll.isScrolling := true
            SetTimer(() => Scroll.Update(), Scroll.updateRate)
        }
    }

    static Update() {
        if (Abs(Scroll.velocity) < 0.1) {
            Scroll.velocity := 0
            Scroll.isScrolling := false
            SetTimer(() => Scroll.Update(), 0)
            return
        }

        ; Apply smoothing/friction
        Scroll.velocity *= (1 - 1 / Scroll.smoothing)

        ; Calculate scroll amount
        scrollAmount := Round(Scroll.velocity)

        if (scrollAmount != 0) {
            if (scrollAmount > 0) {
                MouseClick("WheelUp", , , Abs(scrollAmount))
            } else {
                MouseClick("WheelDown", , , Abs(scrollAmount))
            }
        }
    }

}
