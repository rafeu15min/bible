# -*- coding: utf-8 -*-

"""
Extrator da Bíblia Sagrada (Versão Final e Definitiva)

Este script usa a API biblia.parresia.com como fonte única de dados para
obter a estrutura e o conteúdo da Bíblia. Após a extração, uma função
adicional busca as abreviações na API da Paulus e atualiza o banco de dados.
"""

import requests
import re
import time
import sqlite3
import json
import unicodedata  # Import necessário para as novas funções

# ==============================================================================
# SEU CÓDIGO ORIGINAL (SEM NENHUMA ALTERAÇÃO)
# ==============================================================================


def inicializar_banco_de_dados(db_name='bible.db'):
    """Cria o banco de dados com a estrutura final e simplificada."""
    conn = sqlite3.connect(db_name)
    cursor = conn.cursor()
    cursor.execute("PRAGMA foreign_keys = ON;")

    cursor.execute(
        'CREATE TABLE IF NOT EXISTS Testament (Id_testament INTEGER PRIMARY KEY, Name_testament TEXT NOT NULL UNIQUE)')
    cursor.execute('CREATE TABLE IF NOT EXISTS Book (Id_book INTEGER PRIMARY KEY, Name_book TEXT NOT NULL UNIQUE, Abbreviation_book TEXT, Id_testament INTEGER NOT NULL, FOREIGN KEY (Id_testament) REFERENCES Testament (Id_testament))')
    cursor.execute('CREATE TABLE IF NOT EXISTS Chapter (Id_chapter INTEGER PRIMARY KEY, Number_chapter INTEGER NOT NULL, Id_book INTEGER NOT NULL, FOREIGN KEY (Id_book) REFERENCES Book (Id_book), UNIQUE(Number_chapter, Id_book))')
    cursor.execute('CREATE TABLE IF NOT EXISTS Verse (Id_verse INTEGER PRIMARY KEY, number_verse TEXT NOT NULL, content_verse TEXT NOT NULL, Id_chapter INTEGER NOT NULL, FOREIGN KEY (Id_chapter) REFERENCES Chapter (Id_chapter))')

    print(f"Banco de dados '{db_name}' inicializado com sucesso.")
    conn.commit()
    conn.close()


def obter_lista_de_livros():
    """Usa a API da Parresia para obter la lista completa e oficial de livros."""
    print("Passo 1: Obtendo a lista completa de livros da API...")
    try:
        url = "https://biblia.parresia.com/wp-json/bible/v2/books"
        response = requests.get(url, timeout=15)
        response.raise_for_status()
        livros = response.json()
        print(f" -> Lista de {len(livros)} livros obtida com sucesso.")
        return livros
    except Exception as e:
        print(f" -> Erro fatal ao obter a lista de livros: {e}")
        return None


def extrair_e_processar_capitulo(book_slug, chapter_number, cursor, id_book):
    """
    Usa a API da Parresia, lida com os dois formatos de resposta, agrega versículos
    e os insere no banco de dados. Retorna a abreviação do livro, se encontrada.
    """
    url_api_capitulo = f"https://biblia.parresia.com/wp-json/bible/v2/chapter/{book_slug}_{chapter_number}"

    try:
        response = requests.get(url_api_capitulo, timeout=15)
        response.raise_for_status()
        data = response.json()

        raw_verses = []
        abbreviation = None

        if isinstance(data, list) and data:
            raw_verses = [
                {'value': v.get('number'), 'text': v.get('text')} for v in data]
        elif isinstance(data, dict):
            raw_verses = data.get('versicles', [])
            abbreviation = data.get('bookChildrenAbbreviation')

        versiculos_agrupados = {}
        for v in raw_verses:
            num_str = v.get('value', '').strip()
            texto = v.get('text', '').strip()
            if not num_str or not texto:
                continue

            match = re.match(r'(\d+)', num_str)
            if not match:
                continue

            num_base = match.group(1)
            if num_base not in versiculos_agrupados:
                versiculos_agrupados[num_base] = []
            versiculos_agrupados[num_base].append(texto)

        if not versiculos_agrupados:
            return None

        cursor.execute(
            'INSERT OR IGNORE INTO Chapter (Number_chapter, Id_book) VALUES (?, ?)', (chapter_number, id_book))
        id_chapter = cursor.execute(
            'SELECT Id_chapter FROM Chapter WHERE Number_chapter = ? AND Id_book = ?', (chapter_number, id_book)).fetchone()[0]

        versiculos_para_inserir = []
        for num, textos in sorted(versiculos_agrupados.items(), key=lambda item: int(item[0])):
            texto_completo = " ".join(textos)
            versiculos_para_inserir.append((num, texto_completo, id_chapter))

        if versiculos_para_inserir:
            cursor.executemany(
                'INSERT OR IGNORE INTO Verse (number_verse, content_verse, Id_chapter) VALUES (?, ?, ?);', versiculos_para_inserir)
            print(
                f"      -> Capítulo {chapter_number}: {len(versiculos_para_inserir)} versículos inseridos/agregados.")

        return abbreviation

    except requests.exceptions.HTTPError as e:
        if e.response.status_code in [404, 500]:
            print(
                f"      -> Capítulo {chapter_number} não encontrado. Fim provável do livro.")
        else:
            print(
                f"      -> Erro HTTP {e.response.status_code} na API para o capítulo {chapter_number}.")
        return "Fim"
    except Exception as e:
        print(
            f"      -> Erro inesperado ao processar capítulo {chapter_number}: {e}")
        return "Fim"


def main():
    """Função principal que orquestra todo o processo."""
    db_name = "bible.db"

    inicializar_banco_de_dados(db_name)
    lista_de_livros = obter_lista_de_livros()

    if not lista_de_livros:
        return

    conn = sqlite3.connect(db_name)
    cursor = conn.cursor()
    cursor.execute("PRAGMA foreign_keys = ON;")

    try:
        print("\nPasso 2: Populando o banco de dados...")
        for i, livro_info in enumerate(lista_de_livros):
            nome_livro = livro_info.get('chapter')
            slug_oficial = livro_info.get('slug')
            total_capitulos = livro_info.get('chapter_count')
            nome_testamento_bruto = livro_info.get(
                'meta', {}).get('testament', 'Desconhecido')

            # Padroniza o nome do Testamento
            if nome_testamento_bruto.lower() == 'antigo':
                nome_testamento = 'Antigo Testamento'
            elif nome_testamento_bruto.lower() == 'novo':
                nome_testamento = 'Novo Testamento'
            else:
                nome_testamento = nome_testamento_bruto.capitalize()

            if not all([nome_livro, slug_oficial, total_capitulos]):
                print(
                    f" -> Aviso: Dados incompletos para um livro. Pulando. {livro_info}")
                continue

            print(
                f"\nProcessando Livro {i+1}/{len(lista_de_livros)}: {nome_livro}")

            cursor.execute(
                'INSERT OR IGNORE INTO Testament (Name_testament) VALUES (?)', (nome_testamento,))
            id_testament = cursor.execute(
                'SELECT Id_testament FROM Testament WHERE Name_testament = ?', (nome_testamento,)).fetchone()[0]

            cursor.execute(
                'INSERT OR IGNORE INTO Book (Name_book, Id_testament) VALUES (?, ?)', (nome_livro, id_testament))
            id_book = cursor.execute(
                'SELECT Id_book FROM Book WHERE Name_book = ?', (nome_livro,)).fetchone()[0]

            versiculos_existem = cursor.execute(
                'SELECT 1 FROM Verse INNER JOIN Chapter ON Verse.Id_chapter = Chapter.Id_chapter WHERE Chapter.Id_book = ? LIMIT 1', (id_book,)).fetchone()
            if versiculos_existem:
                print(" -> Livro já populado. Pulando.")
                continue

            abreviacao_salva = False
            for capitulo_atual in range(1, total_capitulos + 1):
                abreviacao = extrair_e_processar_capitulo(
                    slug_oficial, capitulo_atual, cursor, id_book)

                if abreviacao and not abreviacao_salva:
                    cursor.execute(
                        'UPDATE Book SET Abbreviation_book = ? WHERE Id_book = ?', (abreviacao, id_book))
                    abreviacao_salva = True

                if abreviacao == "Fim":  # Sinal de que o livro acabou antes do esperado
                    print(
                        f" -> Fim prematuro detectado. Finalizando o livro '{nome_livro}'.")
                    break

                time.sleep(0.2)

            conn.commit()
            print(f" -> Livro '{nome_livro}' salvo com sucesso.")

    except Exception as e:
        print(f"\nOcorreu um erro geral no processo: {e}")
        conn.rollback()
    finally:
        if conn:
            conn.close()
            print("\n\n--- PROCESSO DE EXTRAÇÃO DE VERSÍCULOS FINALIZADO ---")

# ==============================================================================
# NOVAS FUNÇÕES ADICIONADAS CONFORME SOLICITADO
# ==============================================================================


def slugify(value):
    """Converte uma string em um 'slug' para URLs de forma segura para a API da Paulus."""
    if not isinstance(value, str):
        return ""
    value = unicodedata.normalize('NFKD', value).encode(
        'ascii', 'ignore').decode('ascii')
    value = value.lower().replace(' ', '-')
    return re.sub(r'[^a-z0-9-]', '', value)


def enriquecer_abreviacoes_com_paulus(db_name='bible.db'):
    """
    Após a extração principal, percorre o DB e busca as abreviações
    na API da Paulus para preencher os campos, em ordem.
    """
    print("\nPasso 3: Enriquecendo o banco de dados com as abreviações da Paulus...")
    conn = sqlite3.connect(db_name)
    cursor = conn.cursor()

    paulus_api_base = "https://biblia.paulus.com.br/api/v1/bibles/biblia-pastoral"

    try:
        # 1. Obter a lista ordenada de livros da API da Paulus
        url_paulus_books = "https://biblia.paulus.com.br/api/v1/books"
        data_paulus = requests.get(url_paulus_books, timeout=20).json()
        lista_paulus_ordenada = sorted(
            data_paulus.values(), key=lambda x: x['id'])

        print(
            f" -> Ordem de {len(lista_paulus_ordenada)} livros da Paulus obtida.")

        # 2. Obter todos os livros do nosso banco de dados, na mesma ordem
        cursor.execute("SELECT Id_book, Name_book FROM Book ORDER BY Id_book")
        livros_no_banco = cursor.fetchall()

        if len(lista_paulus_ordenada) != len(livros_no_banco):
            print(" -> AVISO: A quantidade de livros entre a API da Paulus e o banco de dados é diferente. O enriquecimento pode ser impreciso.")

        # 3. Percorrer as duas listas em paralelo
        for livro_paulus, (id_book, nome_livro_db) in zip(lista_paulus_ordenada, livros_no_banco):

            nome_paulus = livro_paulus.get('name')
            grupo_paulus = livro_paulus.get('parent')
            testamento_paulus = livro_paulus.get('testament')

            print(
                f"    -> Processando livro '{nome_livro_db}' (ID: {id_book}) com dados da Paulus: '{nome_paulus}'")

            slug_testamento = slugify(testamento_paulus)
            slug_livro = slugify(nome_paulus)
            slug_grupo = slugify(grupo_paulus) if grupo_paulus else slug_livro

            url_capitulo_paulus = f"{paulus_api_base}/testaments/{slug_testamento}/books/{slug_grupo}/children/{slug_livro}/chapters/1"

            try:
                response = requests.get(url_capitulo_paulus, timeout=10).json()
                abreviacao = response.get('bookChildrenAbbreviation')

                if abreviacao:
                    print(
                        f"      -> Abreviação encontrada: '{abreviacao}'. Atualizando...")
                    cursor.execute(
                        'UPDATE Book SET Abbreviation_book = ? WHERE Id_book = ?', (abreviacao, id_book))
                else:
                    print(
                        f"      -> Nenhuma abreviação retornada pela API para '{nome_paulus}'.")
            except Exception as e:
                print(
                    f"      -> Falha ao buscar abreviação para '{nome_paulus}'. Erro: {e}")

            time.sleep(0.25)

        conn.commit()
        print("\n -> Processo de enriquecimento finalizado.")

    except Exception as e:
        print(
            f"\n -> Ocorreu um erro durante o processo de enriquecimento: {e}")
    finally:
        if conn:
            conn.close()

# ==============================================================================
# PONTO DE ENTRADA DO SCRIPT
# ==============================================================================


if __name__ == "__main__":
    main()
    # Após o main terminar, chama a nova função para buscar as abreviações
    enriquecer_abreviacoes_com_paulus()
