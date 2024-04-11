# ===----------------------------------------------------------------------=== #
# Copyright (c) 2024, Modular Inc. All rights reserved.
#
# Licensed under the Apache License v2.0 with LLVM Exceptions:
# https://llvm.org/LICENSE.txt
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===----------------------------------------------------------------------=== #
"""Implement a generic unsafe pointer type.

You can import these APIs from the `memory` package. For example:

```mojo
from memory.unsafe_pointer import UnsafePointer
```
"""

from sys.info import alignof, sizeof
from sys.intrinsics import _mlirtype_is_eq

from memory.memory import _free, _malloc
from memory.reference import _LITRef


# ===----------------------------------------------------------------------=== #
# UnsafePointer
# ===----------------------------------------------------------------------=== #
@register_passable("trivial")
struct UnsafePointer[
    T: AnyType, address_space: AddressSpace = AddressSpace.GENERIC
](Boolable, CollectionElement, Stringable, Intable, EqualityComparable):
    """This is a pointer type that can point to any generic value that is movable.

    Parameters:
        T: The type the pointer points to.
        address_space: The address space associated with the UnsafePointer allocated memory.
    """

    alias pointer_type = __mlir_type[
        `!kgen.pointer<`, T, `,`, address_space._value.value, `>`
    ]
    """The underlying pointer type."""
    var value: Self.pointer_type
    """The underlying pointer."""

    @always_inline
    fn __init__() -> Self:
        """Create a null pointer.

        Returns:
            A null pointer.
        """
        return Self {
            value: __mlir_attr[`#interp.pointer<0> : `, Self.pointer_type]
        }

    @always_inline
    fn __init__(value: Self.pointer_type) -> Self:
        """Create a pointer with the input value.

        Args:
            value: The MLIR value of the pointer to construct with.

        Returns:
            The pointer.
        """
        return Self {value: value}

    @always_inline
    fn __init__(value: Reference[T, _, _, address_space]) -> Self:
        """Create an unsafe UnsafePointer from a safe Reference.

        Args:
            value: The input reference to construct with.

        Returns:
            The pointer.
        """
        return Self {value: __mlir_op.`lit.ref.to_pointer`(value.value)}

    @always_inline
    fn __init__(*, address: Int) -> Self:
        """Create an unsafe UnsafePointer from an address in an integer.

        Args:
            address: The address to construct the pointer with.

        Returns:
            The pointer.
        """
        return Self {
            value: __mlir_op.`pop.index_to_pointer`[_type = Self.pointer_type](
                Scalar[DType.index](address).value
            )
        }

    @staticmethod
    @always_inline
    fn alloc(count: Int) -> Self:
        """Allocate an array with default alignment.

        Args:
            count: The number of elements in the array.

        Returns:
            The pointer to the newly allocated array.
        """
        return Self(
            address=int(
                _malloc[Int8, address_space=address_space](
                    sizeof[T]() * count, alignment=alignof[T]()
                )
            )
        )

    @staticmethod
    @always_inline("nodebug")
    fn address_of(inout arg: T) -> Self:
        """Gets the address of the argument.

        Args:
            arg: The value to get the address of.

        Returns:
            An UnsafePointer which contains the address of the argument.
        """
        return __mlir_op.`pop.pointer.bitcast`[_type = Self.pointer_type](
            __get_lvalue_as_address(arg)
        )

    @always_inline
    fn free(self):
        """Free the memory referenced by the pointer."""
        Pointer[Int8, address_space=address_space](address=int(self)).free()

    @always_inline
    fn bitcast_element[
        new_type: AnyType
    ](self) -> UnsafePointer[new_type, address_space]:
        """Bitcasts the pointer to a different type.

        Parameters:
            new_type: The target type.

        Returns:
            A new pointer with the specified type and the same address, as
            the original pointer.
        """

        return __mlir_op.`pop.pointer.bitcast`[
            _type = UnsafePointer[new_type, address_space].pointer_type
        ](self.value)

    @always_inline
    fn address_space_cast[
        new_address_space: AddressSpace
    ](self) -> UnsafePointer[T, new_address_space]:
        """Bitcasts the pointer to a different address space.

        Parameters:
            new_address_space: The address space of the result.

        Returns:
            A new pointer with the same type and address, but a new address
            space.
        """

        return __mlir_op.`pop.pointer.bitcast`[
            _type = UnsafePointer[T, new_address_space].pointer_type
        ](self.value)

    @always_inline
    fn __int__(self) -> Int:
        """Returns the pointer address as an integer.

        Returns:
          The address of the pointer as an Int.
        """
        return __mlir_op.`pop.pointer_to_index`[
            _type = __mlir_type.`!pop.scalar<index>`
        ](self.value)

    fn __str__(self) -> String:
        return hex(self)

    @always_inline
    fn __bool__(self) -> Bool:
        """Return true if the pointer is non-null.

        Returns:
            Whether the pointer is null.
        """
        return int(self) != 0

    @always_inline
    fn __add__(self, offset: Int) -> Self:
        """Return a pointer at an offset from the current one.

        Args:
            offset: The offset index.

        Returns:
            An offset pointer.
        """
        return Self(address=int(self) + offset * sizeof[T]())

    @always_inline
    fn __sub__(self, offset: Int) -> Self:
        """Return a pointer at an offset from the current one.

        Args:
            offset: The offset index.

        Returns:
            An offset pointer.
        """
        return self + (-offset)

    @always_inline("nodebug")
    fn __eq__(self, rhs: Self) -> Bool:
        """Returns True if the two pointers are equal.

        Args:
            rhs: The value of the other pointer.

        Returns:
            True if the two pointers are equal and False otherwise.
        """
        return int(self) == int(rhs)

    @always_inline("nodebug")
    fn __ne__(self, rhs: Self) -> Bool:
        """Returns True if the two pointers are not equal.

        Args:
            rhs: The value of the other pointer.

        Returns:
            True if the two pointers are not equal and False otherwise.
        """
        return not (self == rhs)

    @always_inline("nodebug")
    fn __lt__(self, rhs: Self) -> Bool:
        """Returns True if this pointer represents a lower address than rhs.

        Args:
            rhs: The value of the other pointer.

        Returns:
            True if this pointer represents a lower address and False otherwise.
        """
        return int(self) < int(rhs)

    @always_inline("nodebug")
    fn __le__(self, rhs: Self) -> Bool:
        """Returns True if this pointer represents a lower than or equal
           address than rhs.

        Args:
            rhs: The value of the other pointer.

        Returns:
            True if this pointer represents a lower address and False otherwise.
        """
        return int(self) <= int(rhs)

    @always_inline("nodebug")
    fn __gt__(self, rhs: Self) -> Bool:
        """Returns True if this pointer represents a higher address than rhs.

        Args:
            rhs: The value of the other pointer.

        Returns:
            True if this pointer represents a higher than or equal address and False otherwise.
        """
        return int(self) > int(rhs)

    @always_inline("nodebug")
    fn __ge__(self, rhs: Self) -> Bool:
        """Returns True if this pointer represents a higher than or equal
           address than rhs.

        Args:
            rhs: The value of the other pointer.

        Returns:
            True if this pointer represents a higher than or equal address and False otherwise.
        """
        return int(self) >= int(rhs)

    # We're unsafe, so we can have unsafe things. References we make have
    # an immortal mutable lifetime, since we can't come up with a meaningful
    # lifetime for them anyway.
    alias mlir_ref_type = Reference[
        T,
        __mlir_attr.`1: i1`,
        __mlir_attr.`#lit.lifetime<1>: !lit.lifetime<1>`,
        address_space,
    ].mlir_ref_type

    @always_inline
    fn __refitem__(
        self,
    ) -> Self.mlir_ref_type:
        """Return a reference to the underlying data, offset by the offset index.

        Returns:
            A reference to the value.
        """
        return __mlir_op.`lit.ref.from_pointer`[_type = Self.mlir_ref_type](
            self.value
        )

    @always_inline
    fn __refitem__(self, offset: Int) -> Self.mlir_ref_type:
        """Return a reference to the underlying data, offset by the offset index.

        Args:
            offset: The offset index.

        Returns:
            An offset reference.
        """
        return (self + offset).__refitem__()


# ===----------------------------------------------------------------------=== #
# UnsafePointer extensions
# ===----------------------------------------------------------------------=== #
# TODO: These should be methods when we have conditional conformance.


# This isn't a method because destructors only work in the default address
# space.
@always_inline
fn destroy_pointee(ptr: UnsafePointer[_, AddressSpace.GENERIC]):
    """Destroy the pointed-to value.

    The pointer must not be null, and the pointer memory location is assumed
    to contain a valid initialized instance of `T`.

    Args:
        ptr: The pointer whose pointee this destroys.
    """
    _ = __get_address_as_owned_value(ptr.value)


@always_inline
fn move_from_pointee[T: Movable](ptr: UnsafePointer[T, _]) -> T:
    """Move the value at the pointer out.

    The pointer must not be null, and the pointer memory location is assumed
    to contain a valid initialized instance of `T`.

    This performs a _consuming_ move, ending the lifetime of the value stored
    in this pointer memory location. Subsequent reads of this pointer are
    not valid. If a new valid value is stored using `initialize_pointee()`, then
    reading from this pointer becomes valid again.

    Parameters:
        T: The type the pointer points to, which must be `Movable`.

    Args:
        ptr: The pointer whose pointee this moves from.

    Returns:
        The value at the pointer.
    """
    return __get_address_as_owned_value(ptr.value)


@always_inline
fn initialize_pointee[T: Movable](ptr: UnsafePointer[T, _], owned value: T):
    """Emplace a new value into the pointer location.

    The pointer memory location is assumed to contain uninitialized data,
    and consequently the current contents of this pointer are not destructed
    before writing `value`. Similarly, ownership of `value` is logically
    transfered into the pointer location.

    Parameters:
        T: The type the pointer points to, which must be `Movable`.

    Args:
        ptr: The pointer to initialize through.
        value: The value to emplace.
    """
    __get_address_as_uninit_lvalue(ptr.value) = value^


@always_inline
fn move_pointee[T: Movable](*, src: UnsafePointer[T, _], dst: UnsafePointer[T]):
    """Moves the value `src` points to into the memory location pointed to by
    `dest`.

    This performs a consuming move (using `__moveinit__()`) out of the
    memory location pointed to by `src`. Subsequent reads of this
    pointer are not valid unless and until a new, valid value has been
    moved into this pointer's memory location using `initialize_pointee()`.

    This transfers the value out of `self` and into `dest` using at most one
    `__moveinit__()` call.

    Safety:
        * `src` must not be null
        * `src` must contain a valid, initialized instance of `T`
        * `dst` must not be null
        * The contents of `dst` should be uninitialized. If `dst` was
            previously written with a valid value, that value will be be
            overwritten and its destructor will NOT be run.

    Parameters:
        T: The type the pointer points to, which must be `Movable`.

    Args:
        src: Source pointer that the value will be moved from.
        dst: Destination pointer that the value will be moved into.
    """
    __get_address_as_uninit_lvalue(dst.value) = __get_address_as_owned_value(
        src.value
    )