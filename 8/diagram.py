import os
import re

import matplotlib.pyplot as plt


def parse_float(data: str) -> float:
    res = re.findall("\d+\.\d+", data)
    if len(res) < 1:
        raise Exception('в строке нет значений с плавающей точкой')
    return float(res[0])


def parse_dataset(dataset: str) -> dict:
    time_data = []
    tps = []
    lat = []
    for line in dataset.split('\n'):
        splited = line.split(',')
        if len(splited) < 3:
            continue

        tm = parse_float(splited[0])
        time_data.append(tm)
        t = parse_float(splited[1])
        tps.append(t)
        l = parse_float(splited[2])
        lat.append(l)
    return {
        'time': time_data,
        'tps': tps,
        'lat': lat,
    }


def avg_float(items: list) -> float:
    return sum(items) / len(items)


def create_diagram(df_file: str):
    with open(df_file, 'r') as rdr:
        content = rdr.read().strip()

    df = parse_dataset(content)

    fig, ax1 = plt.subplots(figsize=(12, 6))

    ax2 = ax1.twinx()
    ax1.plot(df["time"], df["tps"], color="b", label="tps")
    ax2.plot(df["time"], df["lat"], color="r", label="latency")

    ax1.set_ylabel("Производительность, tps", fontsize=18)
    ax1.set_ylim([400, 800])
    ax1.legend(loc="upper left")

    ax2.set_ylabel("Задержки - latency, ms", fontsize=18)
    ax2.set_ylim([0, 50])
    ax2.legend(loc="upper right")

    ax1.set_xlabel("Время, s")

    diagram_fn = df_file.replace('txt', 'png')
    plt.savefig(diagram_fn)


if __name__ == '__main__':
    df_dir = 'dataframes'
    for _file in os.listdir(df_dir):
        if not _file.endswith('.txt'):
            continue
        df_file = os.path.join(df_dir, _file)
        create_diagram(df_file)
