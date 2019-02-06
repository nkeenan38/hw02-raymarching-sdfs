#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;

in vec2 fs_Pos;
out vec4 out_Col;

#define MAX_DISTANCE 500

struct Scene
{
	float distance;
	float depth;
	int material;
};

float sdSphere(vec3 p, vec3 center, float radius)
{
	mat4 t = mat4(vec4(1.0, 0.0, 0.0, 0.0),
				  vec4(0.0, 1.0, 0.0, 0.0),
				  vec4(0.0, 0.0, 1.0, 0.0),
				  vec4(center.x, center.y, center.z, 1.0));
	p = vec3(inverse(t) * vec4(p.x, p.y, p.z, 1.0));
	return length(p) - radius;
}

float sdBox( vec3 p, vec3 b, vec3 center )
{
	mat4 t = mat4(vec4(1.0, 0.0, 0.0, 0.0),
			  vec4(0.0, 1.0, 0.0, 0.0),
			  vec4(0.0, 0.0, 1.0, 0.0),
			  vec4(center.x, center.y, center.z, 1.0));
	p = vec3(inverse(t) * vec4(p.x, p.y, p.z, 1.0));
    vec3 d = abs(p) - b;
    return length(max(d,0.0))
         + min(max(d.x,max(d.y,d.z)),0.0); // remove this line for an only partially signed sdf 
}

float opSmoothUnion( float d1, float d2, float k ) 
{
    float h = clamp( 0.5 + 0.5*(d2-d1)/k, 0.0, 1.0 );
    return mix( d2, d1, h ) - k*h*(1.0-h); 
}

float opSubtraction( float d1, float d2 ) { return max(-d1,d2); }

float opUnion(float d1, float d2)
{
	return min(d1, d2);
}

vec3 opRep(vec3 p, vec3 c)
{
	return mod(p, c) - 0.5 * c;
}

float gain(float x, float k) 
{
    float a = 0.5*pow(2.0*((x<0.5)?x:1.0-x), k);
    return (x<0.5)?a:1.0-a;
}

bool intersects(vec3 p, vec3 dir, vec3 min, vec3 max)
{
	vec3 tmin, tmax;
    tmin.x = (min.x - p.x) / dir.x; 
    tmax.x = (max.x - p.x) / dir.x; 
 
    if (tmin.x > tmax.x)
    {
    	float tmp = tmin.x;
    	tmin.x = tmax.x;
    	tmax.x = tmp;
    }
 
    tmin.y = (min.y - p.y) / dir.y; 
    tmax.y = (max.y - p.y) / dir.y; 
 
    if (tmin.y > tmax.y)
    {
    	float tmp = tmin.y;
    	tmin.y = tmax.y;
    	tmax.y = tmp;
    }
 
    if ((tmin.x > tmax.y) || (tmin.y > tmax.x)) 
        return false; 
 
    if (tmin.y > tmin.x) 
        tmin.x = tmin.y; 
 
    if (tmax.y < tmax.x) 
        tmax.x = tmax.y; 
 
    tmin.z = (min.z - p.z) / dir.z; 
    tmax.z = (max.z - p.z) / dir.z; 
 
    if (tmin.z > tmax.z)
    {
    	float tmp = tmin.z;
    	tmin.z = tmax.z;
    	tmax.z = tmp;
    }
 
    if ((tmin.x > tmax.z) || (tmin.z > tmax.x)) 
        return false; 
 
    if (tmin.z > tmin.x) 
        tmin.x = tmin.z; 
 
    if (tmax.z < tmax.x) 
        tmax.x = tmax.z; 
 
    return true; 
}

Scene sceneSDF(vec3 p, vec3 dir)
{
	vec3 origin = vec3(0.0);
	float time = u_Time / 40.0;
	float distance = float(MAX_DISTANCE);
	float separation = 4.0;
	float s = (gain((sin(time) + 1.0) / 2.0, 4.0) - 0.5) * 8.0;
	Scene scene;
	scene.distance = distance;
	scene.material = 1;

	if (intersects(p, dir, vec3(-separation-2.25, -2.25, -separation-2.25), vec3(separation+2.25, 4.0, separation+2.25)))
	{
		// (x, y, z, r)
		vec4 spheres[10];
		spheres[0] = vec4(-separation, 0.0, 0.0, 2.25);
		spheres[1] = vec4(-separation, 2.5, 0.0, 1.5);
		spheres[2] = vec4(separation, 0.0, 0.0, 2.25);
		spheres[3] = vec4(separation, 2.5, 0.0, 1.5);
		spheres[4] = vec4(s, 0.0, 0.0, 1.0);

		spheres[5] = vec4(0.0, 0.0, -separation, 2.25);
		spheres[6] = vec4(0.0, 2.5, -separation, 1.5);
		spheres[7] = vec4(0.0, 0.0, separation, 2.25);
		spheres[8] = vec4(0.0, 2.5, separation, 1.5);
		spheres[9] = vec4(0.0, 0.0, s, 1.0);
		float subBox;
		float center;

		if (intersects(p, dir, vec3(-separation-2.25, -2.25, -2.25), vec3(separation+2.25, 4.0, 2.25)))
		{
			// left avocado
			if (intersects(p, dir, vec3(-separation-2.25, -2.25, -2.25), vec3(-separation+2.25, 4.0, 2.25)))
			{
				distance = sdSphere(p, spheres[0].xyz, spheres[0].w);
				distance = opSmoothUnion(distance, sdSphere(p, spheres[1].xyz, spheres[1].w), 1.0);
				subBox = sdBox(p, vec3(1.5, 3.2, 2.3), vec3(-separation + 1.5, 0.875, 0.0));
				if (-subBox > distance)
				{
					scene.material = 2;
				}
				distance = opSubtraction(subBox, distance);
				distance = opSubtraction(sdSphere(p, vec3(-separation, 0.0, 0.0), 1.0), distance);
			}
			if (intersects(p, dir, vec3(separation-2.25, -2.25, -2.25), vec3(separation+2.25, 4.0, 2.25)))
			{
				distance = opUnion(distance, sdSphere(p, spheres[2].xyz, spheres[2].w));
				distance = opSmoothUnion(distance, sdSphere(p, spheres[3].xyz, spheres[3].w), 1.0);
				subBox = sdBox(p, vec3(1.5, 3.2, 2.3), vec3(separation - 1.5, 0.875, 0.0));
				if (-subBox > distance)
				{
					scene.material = 2;
				}
				distance = opSubtraction(subBox, distance);
				distance = opSubtraction(sdSphere(p, vec3(separation, 0.0, 0.0), 1.0), distance);
			}
			if (intersects(p, dir, vec3(s - 1.0, -1.0, -1.0), vec3(s + 1.0, 1.0, 1.0)))
			{
				center = sdSphere(p, spheres[4].xyz, spheres[4].w);

				if (center < distance)
				{
					distance = center;
					scene.material = 0;
				}
			}
		}
		// if (intersects(p, dir, vec3(-2.25, -2.25, -separation-2.25), vec3(2.25, 4.0, separation+2.25)))
		// {
		// 	// back avocado
		// 	if (intersects(p, dir, vec3(-2.25, -2.25, -separation-2.25), vec3(2.25, 4.0, -separation + 2.25)))
		// 	{
		// 		distance = opUnion(distance, sdSphere(p, spheres[5].xyz, spheres[5].w));
		// 		distance = opSmoothUnion(distance, sdSphere(p, spheres[6].xyz, spheres[6].w), 1.0);
		// 		subBox = sdBox(p, vec3(2.3, 3.2, 1.5), vec3(0.0, 0.875, -separation + 1.5));
		// 		if (-subBox > distance)
		// 		{
		// 			scene.material = 2;
		// 		}
		// 		distance = opSubtraction(subBox, distance);
		// 		distance = opSubtraction(sdSphere(p, vec3(0.0, 0.0, -separation), 1.0), distance);			
		// 	}
		// 	// front avocado
		// 	if (intersects(p, dir, vec3(-2.25, -2.25, separation-2.25), vec3(2.25, 4.0, separation+2.25)))
		// 	{
		// 		// distance = opUnion(distance, sdSphere(p, spheres[7].xyz, spheres[7].w));
		// 		// distance = opSmoothUnion(distance, sdSphere(p, spheres[8].xyz, spheres[8].w), 1.0);
		// 		// subBox = sdBox(p, vec3(2.3, 3.2, 1.5), vec3(0.0, 0.875, separation - 1.5));
		// 		// if (-subBox > distance)
		// 		// {
		// 		// 	scene.material = 2;
		// 		// }
		// 		// distance = opSubtraction(subBox, distance);
		// 		// distance = opSubtraction(sdSphere(p, vec3(0.0, 0.0, separation), 1.0), distance);
		// 	}
		// 	if (intersects(p, dir, vec3(-1.0, -1.0, s - 1.0), vec3(1.0, 1.0, s + 1.0)))
		// 	{
		// 		center = sdSphere(p, spheres[9].xyz, spheres[9].w);
		// 		if (center < distance)
		// 		{
		// 			distance = center;
		// 			scene.material = 0;
		// 		}
		// 	}
		// }
	}

	scene.distance = distance;
	return scene;
}


vec3 estNorm(vec3 p, vec3 dir) 
{
	float epsilon = 0.0001;
	return normalize(vec3(
		sceneSDF(vec3(p.x + epsilon, p.y, p.z), dir).distance - sceneSDF(vec3(p.x - epsilon, p.y, p.z), dir).distance,
		sceneSDF(vec3(p.x, p.y + epsilon, p.z), dir).distance - sceneSDF(vec3(p.x, p.y - epsilon, p.z), dir).distance,
		sceneSDF(vec3(p.x, p.y, p.z + epsilon), dir).distance - sceneSDF(vec3(p.x, p.y, p.z - epsilon), dir).distance));
}


Scene rayMarch(vec3 eye, vec3 rayDirection)
{
	float depth = 0.001;
	int maxMarchingSteps = 65;
	Scene scene;
	for (int i = 0; i < maxMarchingSteps; i++)
	{
		scene = sceneSDF(eye + depth * rayDirection, rayDirection);
		if (scene.distance <= 0.01)
		{
			// inside or on surface
			scene.depth = depth;
			return scene;
		}
		depth += scene.distance;

		if (depth >= float(MAX_DISTANCE))
		{
			scene.depth = float(MAX_DISTANCE);
			return scene;
		}
	}
	scene.depth = float(MAX_DISTANCE);
	return scene;
}


void main() {
  float len = distance(u_Ref, u_Eye);
  vec3 forward = normalize(u_Ref - u_Eye);
  vec3 right = cross(forward, u_Up);
  float aspectRatio = u_Dimensions.x / u_Dimensions.y;
  vec3 V = u_Up * len;
  vec3 H = right * len * aspectRatio;
  vec3 p = u_Ref + fs_Pos.x * H + fs_Pos.y * V;
  vec3 dir = normalize(p - u_Eye);
  // vec3 color = 0.5 * (dir + vec3(1.0));
  Scene scene = rayMarch(u_Eye, dir);
  if (scene.depth < float(MAX_DISTANCE))
  {
  	vec3 color;
  	switch (scene.material)
  	{
  		case 0:
  			color = vec3(100.0 / 255.0, 60.0 / 255.0, 30.0 / 255.0);
  			break;
  		case 1:
	  		color = vec3(20.0 / 255.0, 100.0 / 255.0, 20.0 / 255.0);
	  		break;
	  	case 2:
	  		color = vec3(200.0 / 255.0, 200.0 / 255.0, 60.0 / 255.0);
	  		break;
  	}
  	vec4 diffuseColor = vec4(color, 1.0);
  	vec3 norm = estNorm(u_Eye + scene.depth * dir, dir);

  	vec3 lightDir = vec3(0.2, 0.1, 0.7);
	// Calculate the diffuse term for Lambert shading
	float diffuseTerm = dot(norm, normalize(lightDir));
	if (dot(norm, -dir) <= 0.2) diffuseColor = vec4(0.0, 0.0, 0.0, 1.0);
	// Avoid negative lighting values
	diffuseTerm = clamp(diffuseTerm, 0.0f, 1.0f);
	// cartoon lighting
	diffuseTerm = floor(diffuseTerm * 3.0) / 3.0;

	float ambientTerm = 0.3;

	float lightIntensity = diffuseTerm + ambientTerm;   //Add a small float value to the color multiplier
	                                                    //to simulate ambient lighting. This ensures that faces that are not
	                                                    //lit by our point light are not completely black.

	// Compute final shaded color
	out_Col = vec4(diffuseColor.rgb * lightIntensity, diffuseColor.a);
  }
  else
  {
  	out_Col = vec4(vec3(0.5 * (dir + vec3(1.0))), 1.0);
  }
}
  