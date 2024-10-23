; Retrieve Available midi files

; thank god i dont have any passwords in here
SetWorkingDir('G:\Software\Webfishing midi\Mine')

; grabs all midi files from an adjacent directory and creates a GUI
; with a drop down list so the user can select the song to play
SongList := []
loop files "midi\*.mid"
    SongList.InsertAt(0, A_LoopFileName)

SongSelector := Gui()
Dropdown := SongSelector.AddDDL(,SongList)

j::
{
    ShowMenu:
    SongSelector.Show()
    
    KeyWait('space','D')
    SongSelector.Hide()
    WinActivate('WEBFISHING v1.08')
    Main(Dropdown.Value)
    
    goto ShowMenu
}

; these coordinates need to be changed to be relative to the
; window dimensions
UpdateString(String,Finger)
{
    Sendmode 'Input'
    X := 260 + String * 27
    Y := 90 + Finger * 50
    Click X, Y
}

Main(Song)
{
    tabs := midiToEventArray('midi\' SongList[Song])
    tabs := eventArraytoTabs(tabs, tabs[1])


    Click 455, 80
    loop 6
    {
        UpdateString(A_Index,0)
    }

    SetKeyDelay -1, 30

    KeysReference := ['q','w','e','r','t','y']

    Lasts := ['','','','','','']

    for chord in tabs
    {
        if NOT KeyWait('l', 'T0.001')
        {
            break
        }

        if IsNumber(chord)
        {
            tempo := chord
            continue
        }

        PlayKeys := ''

        for n in [1,2,3,4,5,6]
        {
            if isInteger(chord[n]) AND chord[n] != Lasts[n]
            {
                UpdateString(n, chord[n])
                Lasts[n] := chord[n]
            }
            if isInteger(chord[n])
            {
                PlayKeys .= KeysReference[n]
            }
        }

        Sendmode 'Event'
        Send PlayKeys

        Sleep (chord[7]*60000/tempo)-StrLen(PlayKeys)*25
    }
}

midiToEventArray(filename)
{
    MidiFile := FileOpen(filename,0)
    
    MidiFile.RawRead(header := Buffer(4))
    MidiFile.RawRead(headerLength := Buffer(4))
    MidiFile.RawRead(formatType := Buffer(2))
    MidiFile.RawRead(numTracks := Buffer(2))
    MidiFile.RawRead(timeDivision := Buffer(2))

    header := StrGet(header,,'CP0')
    headerLength := BSNumGet(headerLength, 'UInt')
    formatType := BSNumGet(formatType, 'UShort')
    numTracks := BSNumGet(numTracks, 'UShort')
    timeDivision := BSNumGet(timeDivision, 'UShort')
    

    tabsarray := []
    tabsarray.InsertAt(0,timeDivision)

    while MidiFile.Pos < Midifile.Length {
        ;Read chunk parameters
        MidiFile.Pos += 4
        MidiFile.RawRead(chunkLength := Buffer(4))
        chunkLength := BSNumGet(chunkLength, 'UInt')

        lastStatus := 0x00

        ;step into chunk
        while A_Index < chunkLength {

            debugMessage := ''

            deltaTime := parse_var_length(MidiFile)

            MidiFile.RawRead(eventByte := Buffer(1))
            eventByte := NumGet(eventByte, 'UChar')

            if eventByte = 0xFF { ; Meta events
                MidiFile.RawRead(metaType := Buffer(1))
                metaType := NumGet(metaType, 'UChar')

                if deltaTime != 0
                    tabsarray.InsertAt(0,[0,deltaTime])

                if metaType = 0x51 {
                    MidiFile.Pos += 1
                    MidiFile.RawRead(tempoChange := Buffer(3))
                    tempoChange := BSNumGet(tempoChange, "UWide")
                    tabsarray.InsertAt(0,tempoChange)
                    debugMessage := '`ntempo change in position ' . String(tabsarray.Length) . ' from ' . String(MidiFile.Pos-1)
                }
                else if metaType = 0x2F {
                    MidiFile.Pos += 1
                    break
                }
                else {
                    length := parse_var_length(MidiFile)
                    MidiFile.Pos += length
                }
            }
            else If eventByte = 0xF0 or eventByte = 0xF7 {
                length := parse_var_length(MidiFile)
                MidiFile.Pos += length
                if deltaTime != 0
                    tabsarray.InsertAt(0,[0,deltaTime])
            }
            else {
                status:
                if 0x90 <= eventByte AND eventByte <= 0x9F {
                    lastStatus := eventByte
                    MidiFile.RawRead(note := Buffer(1))
                    note := NumGet(note,'UChar')
                    tabsarray.InsertAt(0,[note,deltaTime])
                    MidiFile.Pos += 1
                    debugMessage := '`nnote in position ' . String(tabsarray.Length) . ' from ' . String(MidiFile.Pos-1)
                }
                else if 0x80 <= eventByte AND eventByte <= 0x8F {
                    lastStatus := eventByte
                    MidiFile.Pos += 2
                }
                else if 0xA0 <= eventByte AND eventByte <= 0xBF {
                    lastStatus := eventByte
                    MidiFile.Pos += 2
                }
                else if 0xC0 <= eventByte AND eventByte <= 0xDF {
                    lastStatus := eventByte
                    MidiFile.Pos += 1
                }
                else if 0xE0 <= eventByte AND eventByte <= 0xEF {
                    lastStatus := eventByte
                    MidiFile.Pos += 2
                }
                else{
                    eventByte := lastStatus
                    MidiFile.Pos -= 1
                    goto status
                }
            }
            OutputDebug(debugMessage)
        }
    }
    return tabsarray
}

eventArraytoTabs(array,timeDivision)
{
    array.RemoveAt(1)
    openStrings := [40,45,50,55,59,64]
    tabs := []
    toSort := []
    currentChord := ['','','','','','',0]
    for event in array {
        if IsInteger(event) {
            event := 60000000/event
            tabs.InsertAt(0,event)
        }
        else if event[2] = 0 {
            toSort.InsertAt(0,event[1])
        }
        else if event[2] = 1{
            continue
        }
        else {
            toSort.InsertAt(0,event[1])
            currentChord[7] := event[2]/timeDivision
            for note in toSort {
                if note < 40 OR note > 79
                    continue
                loop 6 {
                    openStr := openStrings[7-A_Index]
                    fret := note - openStr
                    if note >= openStr AND currentChord[7-A_Index] = '' AND fret <= 15 {
                        currentChord[7-A_Index] := fret
                        break
                    }
                }
            }
            tabs.InsertAt(0,currentChord)
            toSort := []
            currentChord := ['','','','','','',0]
            
        }

    }
    return tabs
}

BSNumGet(num, type)
{
    if type = 'UInt' {
        num := NumGet(num, 'UInt')
        num := DllCall("msvcr100\_byteswap_ulong", 'UInt', num, 'UInt')
    }
    else if type = 'UChar'{
        num := DllCall("msvcr100\_byteswap_uint8", "UChar", NumGet(num, type), "UChar")
    }
    else if type = 'UWide'{
        num.Size += 1
        num := NumGet(num,'UInt')
        num := DllCall("msvcr100\_byteswap_ulong", 'UInt', num, 'UInt')
        num >>= 8
        
        
    }
    else
        num := DllCall("msvcr100\_byteswap_" . Format('{:L}',type), type, NumGet(num,Type), type)
    return num
}

parse_var_length(data)
{
    value := 0
    temp := true
    while temp
    {
        data.RawRead(byte := Buffer(1))
        byte := NumGet(byte,'UChar')
        value := (value << 7) | (byte & 0x7F)
        if NOT (byte & 0x80)
            temp := false
    }
    return value

}
