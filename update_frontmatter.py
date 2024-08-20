import sys
from pathlib import Path

import frontmatter


def update_frontmatter(post, date, additional_sources):
    sources_list = [*additional_sources.strip().splitlines()]

    # Update the frontmatter with sources and date
    post.metadata["sources"] = sources_list
    post.metadata["date"] = date

    return post

if __name__ == "__main__":
    file_path = sys.argv[1]
    additional_sources = sys.argv[2]
    date = sys.argv[3]
    # dest_path default file_path

    with Path.open(file_path, encoding="utf-8") as f:
        post = frontmatter.loads(f.read())

    post=update_frontmatter(post, date, additional_sources)

    with Path.open(file_path, "w", encoding="utf-8") as f:
        f.write(frontmatter.dumps(post))
