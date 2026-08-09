using Oxygen
using HTTP
using JSON3
using Sockets
using SQLite
using DBInterface

mutable struct ItemOrdine
    id::String
    numero::Int
    nome::String
    prezzo_riga::Float64
end

# ==============================================================================
# === IMPOSTAZIONI =============================================================
const CHIEDI_NOME_CLIENTE = true

const PRINTER_IP = "192.168.1.XXX"

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
    stmt = DBInterface.prepare(db, "INSERT INTO ordini (totale, nome_cliente, dettaglio_json) VALUES (?, ?, ?)")
    DBInterface.execute(stmt, [totale, nome_cliente, json_str])
end

function invia_a_stampante(prodotti::Vector{String}, totale::Float64)
    # Prepara la sequenza di comandi ESC/POS
    testo = "\x1b\x40" # Comando ESC/POS: Reset della stampante

    # Centra il testo (\x1b\x61\x01) e imposta testo gigante (\x1d\x21\x11)
    testo *= "\x1b\x61\x01\x1d\x21\x11FESTA IN PIAZZA\n\n"

    # Allinea a sinistra (\x1b\x61\x00) e torna a testo normale (\x1d\x21\x00)
    testo *= "\x1d\x21\x00\x1b\x61\x00"
    testo *= "--------------------------------\n"

    # Cicla sui prodotti ordinati e li aggiunge alla stampa
    for prod in prodotti
        testo *= "1x $(uppercase(prod))\n"
    end

    testo *= "--------------------------------\n"
    # Testo in Grassetto (\x1b\x45\x01) per il totale
    testo *= "\x1b\x45\x01TOTALE: $(totale) EUR\x1b\x45\x00\n"

    # Avanzamento carta (\n\n\n) e Taglio della taglierina (\x1d\x56\x00)
    testo *= "\n\n\n\x1d\x56\x00"

    # Apre il socket TCP sulla porta 9100 e invia i byte grezzi
    s = connect(PRINTER_IP, 9100)
    write(s, Vector{UInt8}(testo))
    close(s)
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
        sleep(2)
        # invia_a_stampante(CARRELLO_CORRENTE, totale, nome_cliente)

        totale_corrente = get_totale_corrente()
        salva_ordine_db(totale_corrente, CARRELLO_CORRENTE, nome_cliente)

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
serve(port=8080)
