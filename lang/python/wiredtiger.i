%module wiredtiger

%pythoncode %{
from packing import pack, unpack
%}

/* Set the input argument to point to a temporary variable */ 
%typemap(in, numinputs=0) WT_CONNECTION ** (WT_CONNECTION *temp = NULL) {
        $1 = &temp;
}
%typemap(in, numinputs=0) WT_SESSION ** (WT_SESSION *temp = NULL) {
        $1 = &temp;
}
%typemap(in, numinputs=0) WT_CURSOR ** (WT_CURSOR *temp = NULL) {
        $1 = &temp;
}

/* Set the return value to the returned connection, session, or cursor */
%typemap(argout) WT_CONNECTION ** {
        $result = SWIG_NewPointerObj(SWIG_as_voidptr(*$1),
             SWIGTYPE_p_wt_connection, 0);
}
%typemap(argout) WT_SESSION ** {
        $result = SWIG_NewPointerObj(SWIG_as_voidptr(*$1),
             SWIGTYPE_p_wt_session, 0);
}

%typemap(argout) WT_CURSOR ** {
        (*$1)->flags |= WT_CURSTD_RAW;
        $result = SWIG_NewPointerObj(SWIG_as_voidptr(*$1),
             SWIGTYPE_p_wt_cursor, 0);
        PyObject_SetAttrString($result, "is_column",
            PyBool_FromLong(strcmp((*$1)->key_format, "r") == 0));
}


/* Checking for error returns - any error is an exception.
 * TODO: need to create a wiredtiger exception, probably language specific
 */
%typemap(out) int {
        $result = SWIG_From_int((int)(result));
        if ($1 != 0 && $1 != WT_NOTFOUND) {
                SWIG_exception_fail(SWIG_RuntimeError, wiredtiger_strerror($1));
                return NULL;
        }
}

/*
 * Extra 'self' elimination.
 * The methods we're wrapping look like this:
 * struct wt_xxx {
 *    int method(WT_XXX *, ...otherargs...);
 * };
 * To SWIG, that is equivalent to:
 *    int method(wt_xxx *self, WT_XXX *, ...otherargs...);
 * and we use consecutive argument matching of typemaps to convert two args to one.
 */
%define SELFHELPER(type)
%typemap(in) (type *self, type *) (void *argp = 0, int res = 0) %{
        res = SWIG_ConvertPtr($input, &argp, $descriptor, $disown | 0);
        if (!SWIG_IsOK(res)) { 
                SWIG_exception_fail(SWIG_ArgError(res), "in method '" "$symname" "', argument " "$argnum" " of type '" "$type" "'");
        }
        $2 = $1 = ($ltype)(argp);
%}
%enddef

SELFHELPER(struct wt_connection)
SELFHELPER(struct wt_session)
SELFHELPER(struct wt_cursor)
     
/* WT_CURSOR customization. */
/* First, replace the varargs get / set methods with Python equivalents. */
%ignore wt_cursor::get_key;
%ignore wt_cursor::set_key;
%ignore wt_cursor::get_value;
%ignore wt_cursor::set_value;

/* SWIG magic to turn Python byte strings into data / size. */
%apply (char *STRING, int LENGTH) { (char *data, int size) };

%extend wt_cursor {
        /* Get / set keys and values */
        void _set_key(char *data, int size) {
                WT_ITEM k;
                k.data = data;
                k.size = (uint32_t)size;
                $self->set_key($self, &k);
        }

        void _set_recno(wiredtiger_recno_t recno) {
                $self->set_key($self, recno);
        }

        void _set_value(char *data, int size) {
                WT_ITEM v;
                v.data = data;
                v.size = (uint32_t)size;
                $self->set_value($self, &v);
        }

        PyObject *_get_key() {
                WT_ITEM k;
                $self->get_key($self, &k);
                return SWIG_FromCharPtrAndSize(k.data, k.size);
        }

        wiredtiger_recno_t _get_recno() {
                wiredtiger_recno_t r;
                $self->get_key($self, &r);
                return r;
        }

        PyObject *_get_value() {
                WT_ITEM v;
                $self->get_value($self, &v);
                return SWIG_FromCharPtrAndSize(v.data, v.size);
        }

%pythoncode %{
        def set_key(self, *args):
            if self.is_column:
                self._set_recno(args[0])
            else:
                # Keep the Python string pinned
                self.key = pack(self.key_format, *args)
                self._set_key(self.key)

        def get_key(self):
            if self.is_column:
                return self._get_recno()
            else:
                return unpack(self.key_format, self._get_key())[0]

        def set_value(self, *args):
                # Keep the Python string pinned
                self.value = pack(self.value_format, *args)
                self._set_value(self.value)

        def get_value(self):
                return unpack(self.value_format, self._get_value())[0]

        # Implement the iterable contract for wt_cursor
        def __iter__(self):
                return self

        def next(self):
                try:
                        self._next()
                # TODO: catch wiredtiger exception when there is one?
                except BaseException:
                        raise StopIteration
                return [self.get_key(), self.get_value()]
%}
};

/*
 * We want our own 'next' function for wt_cursor to implement iterable.
 */
%rename(_next) next(WT_CURSOR *);

/* Remove / rename parts of the C API that we don't want in Python. */
%immutable wt_cursor::key_format;
%immutable wt_cursor::value_format;

%ignore WT_BUF;
%ignore wt_collator;
%ignore wt_connection::add_collator;
%ignore wt_cursor_type;
%ignore wt_connection::add_cursor_type;
%ignore wt_event_handler;
%ignore wt_extractor;
%ignore wt_connection::add_extractor;
%ignore wt_item;

%ignore wiredtiger_struct_pack;
%ignore wiredtiger_struct_packv;
%ignore wiredtiger_struct_size;
%ignore wiredtiger_struct_sizev;
%ignore wiredtiger_struct_unpack;
%ignore wiredtiger_struct_unpackv;

%ignore wiredtiger_extension_init;

%rename(Cursor) wt_cursor;
%rename(Session) wt_session;
%rename(Connection) wt_connection;

%include "wiredtiger.h"
