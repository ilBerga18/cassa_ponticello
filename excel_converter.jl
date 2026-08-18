using SQLite
using DBInterface
using DataFrames
using JSON3
using XLSX

# 1. Controlla che sia stato passato il nome del file DB come argomento
if length(ARGS) < 1
    println("Errore: Specifica il nome del file database.")
    println("Uso: julia esporta_excel.jl <nome_file.db>")
    exit(1)
end

db_path = ARGS[1]

if !isfile(db_path)
    println("Errore: Il file '$db_path' non esiste.")
    exit(1)
end

# 2. Connessione al database SQLite passato da argomento
db = SQLite.DB(db_path)

# 2. Lettura di TUTTE le righe dalla tabella ordini
query = "SELECT id, data_ora, totale, nome_cliente, dettaglio_json FROM ordini ORDER BY id ASC"
risultati = DBInterface.execute(db, query)

# Strutture per collezionare i dati
ordini_processati = []
tutti_i_prodotti = Set{String}()

# 3. Primo passaggio: processiamo ogni singolo ordine (1 riga DB)
for riga in risultati
    id_ordine = riga.id
    data_ora = string(riga.data_ora)
    totale = riga.totale
    nome_cliente = coalesce(riga.nome_cliente, "")

    # Mappa dei prodotti per QUESTO specifico ordine (Nome Prodotto => Quantità)
    quantita_prodotti = Dict{String, Int}()

    # Decodifica del JSON
    if !isempty(riga.dettaglio_json)
        dettagli = JSON3.read(riga.dettaglio_json)
        for item in dettagli
            nome_prod = string(item.nome)
            qta = Int(item.numero)

            # Accumula la quantità se il prodotto compare più volte nello stesso ordine
            quantita_prodotti[nome_prod] = get(quantita_prodotti, nome_prod, 0) + qta

            # Registra il nome del prodotto tra i prodotti totali per creare la colonna
            push!(tutti_i_prodotti, nome_prod)
        end
    end

    # Salviamo l'ordine
    push!(ordini_processati, (
        id = id_ordine,
        data_ora = data_ora,
        nome_cliente = nome_cliente,
        totale = totale,
        prodotti = quantita_prodotti
        ))
end

# Ordiniamo i nomi dei prodotti in ordine alfabetico per le colonne dell'Excel
elenco_prodotti = sort(collect(tutti_i_prodotti))

# 4. Costruzione del DataFrame mantenendo la corrispondenza 1:1 con i record originali
df_excel = DataFrame(
    ID = [o.id for o in ordini_processati],
        Data_Ora = [o.data_ora for o in ordini_processati],
            Cliente = [o.nome_cliente for o in ordini_processati],
                Totale = [o.totale for o in ordini_processati]
                    )

# 5. Aggiungiamo una colonna per ogni prodotto trovato nel JSON
for prod_nome in elenco_prodotti
    # Per ogni ordine prendiamo la quantità dal JSON, oppure 0 se non era presente
    df_excel[!, prod_nome] = [get(o.prodotti, prod_nome, 0) for o in ordini_processati]
    end

    # 6. Salva con lo stesso nome del DB ma estensione .xlsx
    output_excel = replace(db_path, r"\.db$"i => "") * ".xlsx"
    XLSX.writetable(output_excel, df_excel)

    println("Completato! Esportati $(nrow(df_excel)) record nel file '$output_excel'.")
