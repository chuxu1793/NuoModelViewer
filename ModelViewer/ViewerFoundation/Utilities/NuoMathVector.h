//
//  NuoMathVector.h
//  ModelViewer
//
//  Created by Dong on 5/10/18.
//  Copyright © 2018 middleware. All rights reserved.
//

#ifndef NuoMathVector_h
#define NuoMathVector_h


template <class itemType, int itemCount> class VectorTrait;


#define USE_SIMD 1


#if __APPLE__ && USE_SIMD

#include "Mac/NuoMathVectorTypeTraitMac.hpp"

#else

#include "Regular/NuoMathVectorTypeTraitRegular.hpp"
    
#endif


template <class itemType, int itemCount>
class NuoVector
{
    
public:
    typedef VectorTrait<itemType, itemCount> _typeTrait;
    typename _typeTrait::_vectorType _vector;

    inline itemType x() const { return _vector.x; }
    inline itemType y() const { return _vector.y; }
    inline itemType z() const { return _vector.z; }
    inline itemType w() const;
    
    inline void x(itemType x) { _vector.x = x; }
    inline void y(itemType y) { _vector.y = y; }
    inline void z(itemType z) { _vector.z = z; }
    inline void w(itemType w);
    
    inline itemType operator[] (size_t i) const { return _vector[i]; }
    
    inline NuoVector(const typename _typeTrait::_vectorType& x) : _vector(x) {};
    
    inline NuoVector() {};
    inline NuoVector(itemType x, itemType y);
    inline NuoVector(itemType x, itemType y, itemType z);
    inline NuoVector(itemType x, itemType y, itemType z, itemType w);
    
    inline const typename _typeTrait::_vectorType&
    operator = (const typename _typeTrait::_vectorType& v)
    {
        return (_vector = v);
    }
    
    inline NuoVector operator - () const;
    
    inline NuoVector Normalize() const
    {
        return NuoVector<itemType, itemCount>(Normalize(_vector));
    }
    
    inline static typename _typeTrait::_vectorType Normalize(const typename _typeTrait::_vectorType& v);
};


template <>
inline float NuoVector<float, 3>::w() const
{
    return 1.0;
}


template <>
inline float NuoVector<float, 4>::w() const
{
    return _vector.w;
}

template <>
inline void NuoVector<float, 4>::w(float w)
{
    _vector.w = w;
}


template <>
inline NuoVector<float, 2>::NuoVector(float x, float y)
{
    _vector.x = x;
    _vector.y = y;
}


template <>
inline NuoVector<float, 3>::NuoVector(float x, float y, float z)
{
    _vector.x = x;
    _vector.y = y;
    _vector.z = z;
}


template <>
inline NuoVector<float, 4>::NuoVector(float x, float y, float z, float w)
{
    _vector.x = x;
    _vector.y = y;
    _vector.z = z;
    _vector.w = w;
}


template <class itemType, int itemCount>
inline NuoVector<itemType, itemCount>
operator - (const NuoVector<itemType, itemCount>& v1, const NuoVector<itemType, itemCount>& v2)
{
    return NuoVector<float, itemCount>(v1._vector - v2._vector);
}

template <class itemType, int itemCount>
inline NuoVector<itemType, itemCount>
operator + (const NuoVector<itemType, itemCount>& v1, const NuoVector<itemType, itemCount>& v2)
{
    return NuoVector<float, itemCount>(v1._vector + v2._vector);
}

template <class itemType, int itemCount>
inline itemType NuoDistance(const NuoVector<itemType, itemCount>& v1, const NuoVector<itemType, itemCount>& v2);

template <class itemType, int itemCount>
inline NuoVector<itemType, itemCount>
operator / (const NuoVector<itemType, itemCount>& v, itemType div);

template <class itemType, int itemCount>
inline NuoVector<itemType, itemCount>
operator * (const NuoVector<itemType, itemCount>& v, itemType div);

template <class itemType, int itemCount>
inline itemType NuoDot(const NuoVector<itemType, itemCount>& v1, const NuoVector<itemType, itemCount>& v2);

template <class itemType, int itemCount>
inline NuoVector<itemType, itemCount>
NuoCross(const NuoVector<itemType, itemCount>& v1, const NuoVector<itemType, itemCount>& v2);


template <class itemType, int dimension>
class NuoMatrix
{
    
public:
    typedef VectorTrait<itemType, dimension> _typeTrait;
    typename _typeTrait::_matrixType _m;
    
    inline NuoMatrix();
    
    inline typename _typeTrait::_vectorType& operator[] (size_t i);
    inline typename _typeTrait::_vectorType operator[] (size_t i) const;
    
    inline NuoMatrix(const typename _typeTrait::_matrixType& v)
    {
        _m = v;
    }
    
    inline const typename _typeTrait::_matrixType&
    operator = (const typename _typeTrait::_matrixType& v)
    {
        return (_m = v);
    }
    
    inline NuoMatrix Inverse() const;
    
    inline bool IsIdentity() const;
};


NuoMatrix<float, 4> NuoMatrixPerspective(float aspect, float fovy, float near, float far);
NuoMatrix<float, 4> NuoMatrixOrthor(float left, float right, float top, float bottom, float near, float far);

NuoMatrix<float, 4> NuoMatrixScale(const NuoVector<float, 3>& scale);
NuoMatrix<float, 4> NuoMatrixRotationAround(NuoMatrix<float, 4> rotate, NuoVector<float, 3> center);
NuoMatrix<float, 4> NuoMatrixLookAt(const NuoVector<float, 3>& eye,
                                    const NuoVector<float, 3>& center,
                                    const NuoVector<float, 3>& up);

template <class itemType, int dimension>
inline bool
operator == (const NuoMatrix<itemType, dimension>& m1, const NuoMatrix<itemType, dimension>& m2);



#if __APPLE__ && USE_SIMD

#include "Mac/NuoMathVectorMac.hpp"

#else

#include "Regular/NuoMathVectorRegular.hpp"

#endif


extern const NuoMatrix<float, 4> NuoMatrixFloat44Identity;
extern const NuoMatrix<float, 3> NuoMatrixFloat34Identity;


inline NuoMatrix<float, 4> NuoMatrixRotation(const NuoVector<float, 3>& axis, float angle)
{
    glm::vec3 gaxis(axis.x(), axis.y(), axis.z());
    glm::mat4x4 gmat = glm::rotate(glm::mat4x4(1.0), -angle, gaxis);
    
    return ToMatrix(gmat);
}


inline NuoMatrix<float, 4> NuoMatrixRotation(float rotateX, float rotateY)
{
    NuoVector<float, 3> xAxis(1, 0, 0);
    NuoVector<float, 3> yAxis(0, 1, 0);
    const NuoMatrix<float, 4> xRot = NuoMatrixRotation(xAxis, rotateX);
    const NuoMatrix<float, 4> yRot = NuoMatrixRotation(yAxis, rotateY);
    
    return xRot * yRot;
}


inline NuoMatrix<float, 4> NuoMatrixTranslation(const NuoVector<float, 3>& t)
{
    glm::vec3 gt(t.x(), t.y(), t.z());
    glm::mat4x4 gmat = glm::translate(glm::mat4x4(1.0), gt);
    
    return ToMatrix(gmat);
}


inline NuoMatrix<float, 4> NuoMatrixRotationAppend(const NuoMatrix<float, 4>& start, float rotateX, float rotateY)
{
    const NuoMatrix<float, 4> rotate = NuoMatrixRotation(rotateX, rotateY);
    return rotate * start;
}



#endif /* NuoMathVector_h */
