#!/usr/bin/env python3

"""
Here you should a short description at least!

Optionally followed by some lines going more
into the details
"""

# bugs and hints: lklemstein@axway.com

import argparse
import logging
import logging.config
import os
import os.path
import sys

from typing import Any, Dict  # , List, Tuple, Callable

type t_setup = Dict[str, Any]

__LOG_LEVEL_DEFAULT = logging.INFO


def main() -> None:
    setup = get_prog_setup_or_exit_with_usage()

    init_logging(setup)
    logger = logging.getLogger(__name__)

    try:
        sys.exit(run(setup))
    except Exception:
        logger.critical("Abort, rc=3", exc_info=True)
        sys.exit(3)


def get_prog_setup_or_exit_with_usage() -> t_setup:
    prog = sys.argv[0]

    if prog.startswith('.'):
        prog = os.path.splitext(prog[2:])[0]

    parser = argparse.ArgumentParser(
                description=get_prog_doc(), prog=prog,
                formatter_class=argparse.RawTextHelpFormatter,
            )

    log_group = parser.add_mutually_exclusive_group()

    parser.add_argument(
        'FIX_ARG_EXAMPLE', help='FIX_ARG is for, well: please say it',
    )

#   parser.add_argument(
#        '--optional_arg', help='an example for an optional arg',
#   )

    log_group.add_argument(
        '--debug', action='store_true',
        help='enable debug log level',
    )

    log_group.add_argument(
        '--log_cfg', dest='log_cfg',
        help='optional logging cfg in ini format',
    )

    args = vars(parser.parse_args())
    args = {k: '' if v is None else v for k, v in args.items()}

    return args


def get_prog_doc() -> str:
    doc_str = sys.modules['__main__'].__doc__

    if doc_str is not None:
        return doc_str.strip()
    else:
        return '<???>'


def init_logging(setup: t_setup) -> None:
    """Creates either a logger by cfg file or a default instance
    with given log level by arg --log_level (otherwise irgnored)

    """
    if setup['log_cfg'] == '':
        if setup['debug']:
            level = logging.DEBUG
            format = '%(levelname)s - %(message)s'
        else:
            level = __LOG_LEVEL_DEFAULT
            format = '%(message)s'

        logging.basicConfig(level=level, format=format)
    else:
        logging.config.fileConfig(setup['log_cfg'])


def run(setup: t_setup) -> int:
    logger = logging.getLogger(__name__)

    #
    # this is the entry point for what your program actually does...
    #

    logger.info('Did something...')

    return 0


if __name__ == '__main__':
    main()
