# distutils: language = c++
# cython: language_level=3, cdivision=True, c_string_type=bytes, c_string_encoding=ascii

from libc.math cimport log2, M_PI, pow
from libc.stdint cimport uint64_t
from libcpp.string cimport string
from libcpp.vector cimport vector

from ._cpython cimport _Py_HashDouble, Py_hash_t, Py_uhash_t
from ._json cimport Json
from .const cimport EARTH_RADIUS_KILOMETERS, EARTH_RADIUS_METERS
from .geo.s2 cimport S2Point
from .geo.s2cellid cimport S2CellId
from .geo.s2latlng cimport S2LatLng
from .geo.s2latlngrect cimport S2LatLngRect
from .geo.s2loop cimport S2Loop
from .geo.s2polygonbuilder cimport S2PolygonBuilder
from .geo.s2regioncoverer cimport S2RegionCoverer
from .location cimport Location
from .utils cimport coords_to_s2point, s2point_to_lat, s2point_to_lon


cdef class Polygon:
    def __cinit__(self, tuple boundaries, tuple holes=None):
        cdef:
            tuple points
            double lat, lon
            vector[S2Point] pv
            S2Point a, b, c
            S2PolygonBuilder builder
            S2PolygonBuilder.EdgeList edge_list

        for points in boundaries:
            self.create_loop(points, &builder, 0)

        if holes:
            for points in holes:
                self.create_loop(points, &builder, 1)

        builder.AssemblePolygon(&self.shape, &edge_list)
        cdef S2LatLngRect rect = self.shape.GetRectBound()
        self.south = rect.lat_lo().degrees()
        self.east = rect.lng_hi().degrees()
        self.north = rect.lat_hi().degrees()
        self.west = rect.lng_lo().degrees()

    cdef void create_loop(self, tuple points, S2PolygonBuilder* builder, int depth):
        cdef:
            vector[S2Point] v
            S2Loop loop
        for coords in points:
            lat, lon = coords
            v.push_back(coords_to_s2point(lat, lon))
        loop.Init(v)
        # if loop covers more than half of the Earth's surface it was probably
        # erroneously constructed clockwise
        if loop.GetArea() > (M_PI * 2):
            loop.Invert()
        loop.set_depth(depth)
        builder.AddLoop(&loop)

    def __bool__(self):
        return True

    def __hash__(self):
        cdef Py_uhash_t mult = 1000003
        cdef Py_uhash_t x = 0x345678
        cdef Py_hash_t y

        cdef double[5] inputs = [self.south, self.east, self.north, self.west, <double>self.shape.num_vertices()]
        cdef double i
        for i in inputs:
            y = _Py_HashDouble(i)
            x = (x ^ y) * mult
            mult += <Py_hash_t>(82520 + 10)
        return x + 97531

    def __contains__(self, Location loc):
        return self.shape.Contains(loc.point)

    def get_points(self, int level):
        cdef S2RegionCoverer coverer
        coverer.set_min_level(level)
        coverer.set_max_level(level)
        cdef vector[S2Point] points
        coverer.GetPoints(self.shape, &points)
        cdef size_t i, size = points.size()
        for i in range(size):
            yield Location.from_point(points.back())
            points.pop_back()

    def contains_cellid(self, uint64_t cellid):
        return self.shape.Contains(S2CellId(cellid << (63 - <int>log2(cellid))).ToPointRaw())

    def contains_token(self, unicode t):
        return self.shape.Contains(S2CellId.FromToken(t).ToPointRaw())

    def distance(self, Location loc):
        return self.shape.GetDistance(loc.point).radians() * EARTH_RADIUS_METERS

    def project(self, Location loc):
        return Location.from_point(self.shape.Project(loc.point))

    @property
    def json(self):
        cdef:
            Json.object_ jobject
            Json.array areas, area, coords, holes
            S2Loop* loop
            S2Point vertex
            int i, ii, vertices, loops = self.shape.num_loops()

        coords = Json.array(<size_t>2)

        for i in range(loops):
            loop = self.shape.loop(i)
            vertices = loop.num_vertices()
            for ii in range(vertices):
                vertex = loop.vertex(ii)
                coords[0] = Json(s2point_to_lat(vertex))
                coords[1] = Json(s2point_to_lon(vertex))
                area.push_back(Json(coords))

            area.push_back(area.front())
            if loop.is_hole():
                holes.push_back(Json(area))
            else:
                areas.push_back(Json(area))
            area.clear()

        jobject[string(b'areas')] = Json(areas)
        jobject[string(b'holes')] = Json(holes)
        return Json(jobject).dump()

    @property
    def center(self):
        return Location.from_point(self.shape.GetCentroid())

    @property
    def bounds(self):
        return self.south, self.east, self.north, self.west

    @property
    def area(self):
        """Returns the square kilometers for configured area"""
        return self.shape.GetArea() * pow(EARTH_RADIUS_KILOMETERS, 2)
