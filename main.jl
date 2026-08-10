using Oxygen
using HTTP
using JSON3
using Sockets
using SQLite
using DBInterface
using Printf
using Dates
using FileIO
using Images

mutable struct ItemOrdine
    id::String
    numero::Int
    nome::String
    prezzo_riga::Float64
end

# ==============================================================================
# === IMPOSTAZIONI =============================================================
const CHIEDI_NOME_CLIENTE = true

const PRINTER_IP = "127.0.0.1"

const PRODOTTI = [
    Dict("id" => "s_vuo",       "nome" => "Vuoto",              "prezzo" => 2.00, "categoria" => "cibo"),
    Dict("id" => "s_str",       "nome" => "Stracchino",         "prezzo" => 3.50, "categoria" => "cibo"),
    Dict("id" => "s_cop_str",   "nome" => "Coppa Stracchino",   "prezzo" => 4.00, "categoria" => "cibo"),
    Dict("id" => "s_pan_str",   "nome" => "Pancetta Stracchino","prezzo" => 4.00, "categoria" => "cibo"),
    Dict("id" => "s_sal_str",   "nome" => "Salame Stracchino",  "prezzo" => 4.00, "categoria" => "cibo"),
    Dict("id" => "s_cop",       "nome" => "Coppa",              "prezzo" => 3.50, "categoria" => "cibo"),
    Dict("id" => "s_pan",       "nome" => "Pancetta",           "prezzo" => 3.50, "categoria" => "cibo"),
    Dict("id" => "s_sal",       "nome" => "Salame",             "prezzo" => 3.50, "categoria" => "cibo"),
    Dict("id" => "s_nut",       "nome" => "Nutella",            "prezzo" => 3.50, "categoria" => "cibo"),

    Dict("id" => "birra",       "nome" => "Birra",              "prezzo" => 4.00, "categoria" => "bar"),
    Dict("id" => "nat1",        "nome" => "Naturale 1L",        "prezzo" => 2.00, "categoria" => "bar"),
    Dict("id" => "gas1",        "nome" => "Frizzante 1L",       "prezzo" => 2.00, "categoria" => "bar"),
    Dict("id" => "nat05",       "nome" => "Naturale 0.5L",      "prezzo" => 1.00, "categoria" => "bar"),
    Dict("id" => "gas05",       "nome" => "Frizzante 0.5L",     "prezzo" => 1.00, "categoria" => "bar"),
    Dict("id" => "coca",        "nome" => "CocaCola",           "prezzo" => 3.00, "categoria" => "bar"),
    Dict("id" => "te",          "nome" => "EstaThe",            "prezzo" => 2.00, "categoria" => "bar"),
    Dict("id" => "aran",        "nome" => "Aranciata",          "prezzo" => 3.00, "categoria" => "bar")
]


# ==============================================================================
# === RUNTIME VARIABLES ========================================================
CARRELLO_CORRENTE = ItemOrdine[]

LISTINO_PREZZI = Dict(prod["id"] => prod["prezzo"] for prod in PRODOTTI)
LISTINO_NOMI = Dict(prod["id"] => prod["nome"] for prod in PRODOTTI)
LISTINO_CAT = Dict(prod["id"] => prod["categoria"] for prod in PRODOTTI)


# ==============================================================================
# === FUNZIONI =================================================================
function get_totale_corrente()
    if isempty(CARRELLO_CORRENTE)
        return 0.0
    end
    return sum(item.numero * get(LISTINO_PREZZI, item.id, 0.0) for item in CARRELLO_CORRENTE)
end

function salva_ordine_db(totale::Float64, carrello::Vector{ItemOrdine}, nome_cliente::String)
    # Converte il vettore del carrello in una stringa JSON
    json_str = JSON3.write(carrello)

    # Inserisce il record nel DB
    DBInterface.execute(
        db,
        "INSERT INTO ordini (totale, nome_cliente, dettaglio_json) VALUES (?, ?, ?)",
        [totale, nome_cliente, json_str])

    stmt = DBInterface.execute(db, "SELECT last_insert_rowid()")
    id_ordine = first(stmt)[1]

    return id_ordine
end

function genera_html_scontrino(tipo::Symbol; progressivo::Int, nome_cliente::String, items=Any[], data_str::String="", totale::Float64=0.0)

    # 1. RICEVUTA CLIENTE
    if tipo == :ricevuta
        rows_html = ""
        for item in items
            rows_html *= """
            <tr>
            <td class="col-qta"><span class="qta-pill">$(item.numero)×</span></td>
            <td class="col-nome">$(item.nome)</td>
            <td class="col-prezzo">$(@sprintf("€ %.2f", item.prezzo_riga))</td>
            </tr>
            """
        end

        cliente_html = !isempty(nome_cliente) ? "<div><strong>CLIENTE:</strong>$(uppercase(nome_cliente))</div>" : ""

        return """
        <!DOCTYPE html>
        <html lang="it">
        <head>
        <meta charset="UTF-8">
        <link rel="stylesheet" href="$(pwd())/public/ricevuta.css">
        </head>
        <body>

        <div class="ticket-card">

        <div class="header">
        <div class="festa-title">Festa di Ponticello</div>
        <h1 class="festa-sub">"I mestieri del borgo"</h1>
        </div>

        <div class="order-hero">
        <div class="order-label">Numero Ordine</div>
        <div class="order-number">#$(progressivo)</div>
        </div>

        <div class="meta-box">
        $(cliente_html)
        <div>$(data_str)</div>
        </div>

        <table>
        <thead>
        <tr>
        <th class="col-qta">Qtà</th>
        <th class="col-nome">Descrizione</th>
        <th class="col-prezzo">Importo</th>
        </tr>
        </thead>
        <tbody>
        $(rows_html)
        </tbody>
        </table>

        <div class="totale-box">
        <span class="totale-label">Totale</span>
        <span class="totale-valore">$(@sprintf("€ %.2f", totale))</span>
        </div>

        <div class="footer">
        Grazie e buon appetito!
        </div>

        </div>

        </body>
        </html>
        """

        # 2. BUONO RITIRO BAR
        elseif tipo == :bar
        rows_html = ""
        for item in items
            rows_html *= """
            <tr>
            <td class="col-qta"><span class="qta-pill">$(item.numero)×</span></td>
            <td class="col-nome">$(item.nome)</td>
            </tr>
            """
        end

        return """
        <!DOCTYPE html>
        <html lang="it">
        <head>
        <meta charset="UTF-8">
        <link rel="stylesheet" href="$(pwd())/public/ricevuta.css">
        </head>
        <body>

        <div class="ticket-card">

        <div class="header">
        <div class="header-top">
        <span class="festa-title">Ponticello — I mestieri del borgo</span>
        <span class="order-number-small">Ord. #$(progressivo)</span>
        </div>
        <div class="tipo-scontrino">RITIRO BEVANDE BAR</div>
        <div class="meta-instruction">Consegna questo buono al banco bar</div>
        </div>

        <table>
        <tbody>
        $(rows_html)
        </tbody>
        </table>
        </div>

        </body>
        </html>
        """

    # 3. COMANDA CUCINA
    elseif tipo == :cucina
        items_html = ""
        for item in items
            items_html *= """
            <tr>
            <td class="col-qta"><span class="qta-pill">$(item.numero)×</span></td>
            <td class="col-nome">$(item.nome)</td>
            </tr>
            """
        end

        cliente_block = !isempty(nome_cliente) ? "<div class='badge-cliente'>CLIENTE: $(uppercase(nome_cliente))</div>" : ""

        return """
        <!DOCTYPE html>
        <html lang="it">
        <head>
        <meta charset="UTF-8">
        <link rel="stylesheet" href="$(pwd())/public/ricevuta.css">
        </head>
        <body>

        <div class="ticket-card ticket-cucina">

        <div class="header">
        <div class="tipo-scontrino">COMANDA CUCINA</div>
        </div>

        <div class="order-hero">
        <div class="order-label">Numero Ordine</div>
        <div class="order-number">#$(progressivo)</div>
        $(cliente_block)
        </div>

        <table>
        <tbody>
        $(items_html)
        </tbody>
        </table>
        </div>

        </body>
        </html>
        """
    end
end

function html_to_png(html_content::String, output_png_path::String)
    temp_html = tempname() * ".html"
    write(temp_html, html_content)

    # Renderizza l'HTML direttamente in PNG impostando la larghezza a 576px
    cmd = `wkhtmltoimage --enable-local-file-access --encoding utf-8 --width 576 --quality 100 $temp_html $output_png_path`
    run(cmd)

    rm(temp_html, force=true)
end

function image_to_escpos_raster(img_path::String)::Vector{UInt8}
    img = load(img_path)

    # Converte in scala di grigi e poi in binarizzato (soglia 0.5)
    gray_img = Gray.(img)
    width, height = size(gray_img, 2), size(gray_img, 1)

    # Larghezza in byte (deve essere multiplo di 8, per 576px -> 72 byte)
    width_bytes = div(width + 7, 8)

    buffer = IOBuffer()

    # Comando ESC/POS GS v 0 (Print raster bit image)
    # GS v 0 m xL xH yL yH
    write(buffer, UInt8[0x1D, 0x76, 0x30, 0x00]) # Mode 0 = Normal
    write(buffer, UInt8(width_bytes % 256))
    write(buffer, UInt8(width_bytes ÷ 256))
    write(buffer, UInt8(height % 256))
    write(buffer, UInt8(height ÷ 256))

    # Binarizzazione e compattazione bit-by-bit
    for y in 1:height
        for x_byte in 0:(width_bytes - 1)
            byte_val = 0x00
            for bit in 0:7
                x = x_byte * 8 + bit + 1
                if x <= width
                    # Se il pixel è scuro (valore basso), imposta il bit a 1 (punto nero)
                    if real(gray_img[y, x]) < 0.5
                        byte_val |= (0x80 >> bit)
                    end
                end
            end
            write(buffer, UInt8(byte_val))
        end
    end

    return take!(buffer)
end

function crea_stream_grafico(progressivo::Integer, nome_cliente::String)
    items_bar = filter(i -> LISTINO_CAT[i.id] == "bar", CARRELLO_CORRENTE)
    items_cibo = filter(i -> LISTINO_CAT[i.id] == "cibo", CARRELLO_CORRENTE)

    ora_attuale = now()
    data_formattata = Dates.format(ora_attuale, "dd/mm/yyyy HH:MM")
    totale = get_totale_corrente()

    stream_buf = IOBuffer()

    # Comandi ESC/POS di Inizializzazione e Taglio
    INIT = UInt8[0x1B, 0x40]
    CUT  = UInt8[0x1D, 0x56, 0x00, 0x0A] # Cut con avanzamento carta

    # --- SEGMENTO 1: RICEVUTA CLIENTE ---
    html_ric = genera_html_scontrino(:ricevuta; progressivo=progressivo, nome_cliente=nome_cliente,
                                     items=CARRELLO_CORRENTE, data_str=data_formattata, totale=totale)
    file_ric = tempname() * ".png"
    html_to_png(html_ric, file_ric)

    write(stream_buf, INIT)
    write(stream_buf, image_to_escpos_raster(file_ric))
    write(stream_buf, CUT)
    rm(file_ric, force=true)

    # --- SEGMENTO 2: BUONO BAR ---
    if !isempty(items_bar)
        html_bar = genera_html_scontrino(:bar; progressivo=progressivo, nome_cliente=nome_cliente, items=items_bar)
        file_bar = tempname() * ".png"
        html_to_png(html_bar, file_bar)

        write(stream_buf, INIT)
        write(stream_buf, image_to_escpos_raster(file_bar))
        write(stream_buf, CUT)
        rm(file_bar, force=true)
    end

    # --- SEGMENTO 3: COMANDA CUCINA ---
    if !isempty(items_cibo)
        html_cuc = genera_html_scontrino(:cucina; progressivo=progressivo, nome_cliente=nome_cliente, items=items_cibo)
        file_cuc = tempname() * ".png"
        html_to_png(html_cuc, file_cuc)

        write(stream_buf, INIT)
        write(stream_buf, image_to_escpos_raster(file_cuc))
        write(stream_buf, CUT)
        rm(file_cuc, force=true)
    end

    return take!(stream_buf)
end


# ==============================================================================
# === INIZIALIZZAZIONE =========================================================

println("=== Avvio del database ===")

# crea automaticamente un file "cassa_festa.db" nella cartella del progetto
const db = SQLite.DB("cassa.db")

# Crea la tabella degli ordini se non è già presente
DBInterface.execute(db, """
                    CREATE TABLE IF NOT EXISTS ordini (
                        id INTEGER PRIMARY KEY AUTOINCREMENT,
                        data_ora DATETIME DEFAULT CURRENT_TIMESTAMP,
                        totale REAL NOT NULL,
                        nome_cliente TEXT,
                        dettaglio_json TEXT NOT NULL
                        );
                        """)

println("=== Database SQLite pronto e sincronizzato ===")



# ==============================================================================
# === ROUTE HTTP ===============================================================
staticfiles("public")

# Inizializza i vari prodotti coi prezzi
@get "/api/prodotti" function()
    return json(PRODOTTI)
end

# Comunica le imopstazioni del front end
@get "/api/config" function()
    return json(
        Dict("chiedi_nome" => CHIEDI_NOME_CLIENTE)
        )
end

# Rende disponibile la pagina principale
@get "/" function()
    return file("public/index.html")
end

# Rende disponibile la pagina dello storico
@get "/storico" function()
    return file("public/storico.html")
end

# API che estrae tutti gli ordini dal database SQLite e li invia come JSON
@get "/api/storico" function()
    # Query per selezionare tutti gli ordini (dal più recente al più vecchio)
    query = "SELECT id, data_ora, totale, nome_cliente, dettaglio_json FROM ordini ORDER BY id DESC"
    risultati = DBInterface.execute(db, query)

    lista_ordini = []
    for riga in risultati
        push!(lista_ordini, Dict(
            "id"           => riga.id,
            "data_ora"     => string(riga.data_ora),
            "totale"       => riga.totale,
            "nome_cliente" => coalesce(riga.nome_cliente, "N/A"),
            # Converte il JSON salvato nel DB in un array leggibile dal browser
            "dettaglio"    => JSON3.read(riga.dettaglio_json)
            ))
    end

    return json(lista_ordini)
end

# Chiamata effettuata ogni volte che viene aggiunto qualcosa al carrello
@post "/api/aggiungi" function(req::HTTP.Request)
    dati_ricevuti = JSON3.read(req.body)
    id_prodotto = dati_ricevuti.id

    # cerca se il prodotto è presente nel carrello
    idx = findfirst(item -> item.id == id_prodotto, CARRELLO_CORRENTE)

    if isnothing(idx)
        push!(CARRELLO_CORRENTE, ItemOrdine(id_prodotto, 1, LISTINO_NOMI[id_prodotto], LISTINO_PREZZI[id_prodotto]))
    else
        CARRELLO_CORRENTE[idx].numero += 1
        CARRELLO_CORRENTE[idx].prezzo_riga += LISTINO_PREZZI[id_prodotto]
    end
    
    totale_corrente = get_totale_corrente()
    
    # Invia al browser lo stato agigornato
    return json(Dict(
        "carrello" => CARRELLO_CORRENTE,
        "totale"   => totale_corrente
    ))
end

# Chiamata quando si preme il tasto Annulla
@post "/api/svuota" function(req::HTTP.Request)
    empty!(CARRELLO_CORRENTE)
    return json(Dict("carrello" => CARRELLO_CORRENTE, "totale" => 0.0))
end


@post "/api/stampa" function(req::HTTP.Request)
    if isempty(CARRELLO_CORRENTE)
        return HTTP.Response(400, "Carrello vuoto")
    end

    body = JSON3.read(req.body)
    nome_cliente = get(body, :nome, "")

    try
        totale_corrente = get_totale_corrente()
        progressivo = salva_ordine_db(totale_corrente, CARRELLO_CORRENTE, nome_cliente)

        payload_stampa = crea_stream_grafico(progressivo, nome_cliente)

        #try
            # Apre la connessione socket con l'IP della stampante
            #sock = connect(PRINTER_IP, 9100)

            # Invia i dati binari/stringa ESC/POS
            # write(sock, payload_stampa)

            # Chiude la connessione
            #close(sock)
            #println("Scontrino inviato con successo a $PRINTER_IP:9100")
        #catch e
        #    println("Errore di connessione alla stampante: $e")
        #    rethrow(e)
        #end

        empty!(CARRELLO_CORRENTE)

        return json(Dict("status" => "ok"))
    catch e
        return HTTP.Response(500, "Errore: $e")
    end
end

# Restituisce lo stato attuale del carrello memorizzato sul server
@get "/api/carrello" function()
    return json(Dict(
        "carrello" => CARRELLO_CORRENTE,
        "totale"   => get_totale_corrente()
        ))
end


# ==============================================================================
# === AVVIO DEL SERVER =========================================================
println("=== Server Cassa avviato su http://localhost:8080 ===")
serve(host="0.0.0.0", port=8080)
