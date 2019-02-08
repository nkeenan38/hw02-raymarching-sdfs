#version 300 es
precision highp float;

uniform vec3 u_Eye, u_Ref, u_Up;
uniform vec2 u_Dimensions;
uniform float u_Time;
uniform int u_ShaderMode;
uniform float u_Ripeness;

in vec2 fs_Pos;
out vec4 out_Col;

#define MAX_DISTANCE 1000

vec3 BROWN = vec3(100.0 / 255.0, 60.0 / 255.0, 30.0 / 255.0);
vec3 LIGHT_BROWN = vec3(140.0 / 255.0, 100.0 / 255.0, 40.0 / 255.0);
vec3 GREEN()
{
	return mix(vec3(0.0 / 255.0, 150.0 / 255.0, 20.0 / 255.0), vec3(0.0 / 255.0, 40.0 / 255.0, 0.0 / 255.0), u_Ripeness);
}
vec3 YOLK = vec3(200.0 / 255.0, 200.0 / 255.0, 60.0 / 255.0);
vec3 YELLOW()
{
	return mix(vec3(50.0 / 255.0, 120.0 / 255.0, 0.0 / 255.0), vec3(200.0 / 255.0, 200.0 / 255.0, 60.0 / 255.0), u_Ripeness);
}
vec3 WHITE = vec3(1.0);

struct Scene
{
	float distance;
	float depth;
	vec3 color;
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

float sdCapsule( vec3 p, vec3 a, vec3 b, float r)
{
    vec3 pa = p - a, ba = b - a;
    float h = clamp( dot(pa,ba)/dot(ba,ba), 0.0, 1.0 );
    return length( pa - ba*h ) - r;
}

float sdRoundedCylinder( vec3 p, float ra, float rb, float h, vec3 center)
{
	mat4 t = mat4(vec4(1.0, 0.0, 0.0, 0.0),
		  vec4(0.0, 1.0, 0.0, 0.0),
		  vec4(0.0, 0.0, 1.0, 0.0),
		  vec4(center.x, center.y, center.z, 1.0));
	p = vec3(inverse(t) * vec4(p.x, p.y, p.z, 1.0));
    vec2 d = vec2( length(p.xz)-2.0*ra+rb, abs(p.y) - h );
    return min(max(d.x,d.y),0.0) + length(max(d,0.0)) - rb;
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
    float a = 0.5* pow(2.0 * ((x<0.5) ? x : 1.0 - x), k);
    return (x < 0.5) ? a : 1.0 - a;
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

vec3 rep(vec3 p)
{
	return (opRep(p, vec3(24.0, 16.0, 0.0)));
}

Scene sceneSDF(vec3 p, vec3 dir)
{
	/***** Dimensions *****/
	const float AVO_RAD_L = 2.25;
	const float AVO_RAD_S = 1.5;
	const float AVO_AMP = 8.0;

	const float SEED_RAD = 1.0;
	const float SEED_AMP = 8.0; 

	const float EGG_RAD = 3.0;

	const float FLOOR_RAD = 50.0;

	vec3 origin = vec3(0.0);
	float time = u_Time / 40.0;
	float distance = float(MAX_DISTANCE);
	float t = gain((sin(time) + 1.0) / 2.0, 3.0);
	float diff = t - gain((sin(time - 1.0) + 1.0) / 2.0, 3.0);
	bool increasing = diff >= 0.0;;
	float r = (t + pow((-abs(diff)+1.0), 4.0) * 0.12);
	float q = t > 0.8 ? (t - 0.8)*2.0 : 0.0;
	float s = t * AVO_AMP;

	Scene scene;
	scene.distance = distance;
	scene.color = GREEN();

	// (x, y, z, r)
	vec4 spheres[3];
	spheres[0] = vec4(s-0.03, 0.0, 0.0, AVO_RAD_L);			// large part of avocado
	spheres[1] = vec4(s-0.03, 2.5, 0.0, AVO_RAD_S);			// small part of avocado
	spheres[2] = vec4(0.0, (-t) * SEED_AMP, 0.0, SEED_RAD); // seed

	float subBoxLeft, subBoxRight;
	bool subLeft, subRight;
	float center = float(MAX_DISTANCE);
	float avocado = float(MAX_DISTANCE);

	if (intersects(p, dir, vec3(-AVO_AMP-AVO_RAD_L, -SEED_AMP-SEED_RAD, -EGG_RAD), vec3(AVO_AMP+AVO_RAD_L, float(MAX_DISTANCE), EGG_RAD)))
	{
		/****** Avocado Section *****/

		// symmetry for avocados, reflects x-axis, repeats in the y
		vec3 symX = vec3(abs(p.x), (mod((p.y + AVO_RAD_L), 16.0) - AVO_RAD_L), p.z);

		if (intersects(p, dir, vec3(-spheres[0].x-AVO_RAD_L, -AVO_RAD_L, -AVO_RAD_L), vec3(spheres[0].x+AVO_RAD_L, float(MAX_DISTANCE), AVO_RAD_L)))
		{
			avocado = opUnion(avocado, sdSphere(symX, spheres[0].xyz, spheres[0].w));
			avocado = opSmoothUnion(avocado, sdSphere(symX, spheres[1].xyz, spheres[1].w), 1.0);

			// cuts avocado in halves
			subBoxRight = sdBox(symX, vec3(1.155, 3.15, 2.5), vec3(spheres[0].x - 1.125, 0.875, 0.0));
			if (-subBoxRight > avocado + 0.25)
			{
				// colors the inside yellow
				scene.color = YELLOW();
			}
			avocado = opSubtraction(subBoxRight, avocado);
			avocado = opSubtraction(sdSphere(symX, vec3(spheres[0].x, 0.0, 0.0), 1.0), avocado);
			distance = avocado;
		}

		/***** Avocado Pit / Egg Yolk Section *****/

		if (intersects(p, dir, vec3(-EGG_RAD, -SEED_AMP, -EGG_RAD), vec3(EGG_RAD, MAX_DISTANCE, EGG_RAD)))
		{
			if (increasing)
			{
				center = sdSphere(vec3(p.x, mod(p.y + 8.0, 16.0) - 8.0, p.z), spheres[2].xyz, spheres[2].w);
			}
			else
			{
				center = opSmoothUnion(center, sdSphere(vec3(p.x, mod(p.y+1.0, 16.0) - 1.0, p.z), vec3(spheres[2].x, -spheres[2].y, spheres[2].z), spheres[2].w), 1.0);
			}
			if (center < distance)
			{
				distance = center;
				scene.color = mix(BROWN, YOLK, r);
			}

			/***** Egg White Section *****/

			float eggWhite = sdRoundedCylinder(vec3(p.x, mod(p.y + 8.0, 16.0) - 8.0, p.z), q*3.0, r*0.15, r*0.05, vec3(0.0, -8.0, 0.0));
			eggWhite = opUnion(eggWhite, sdRoundedCylinder(vec3(p.x, mod(p.y, 16.0), p.z), q*3.0, r*0.15, r*0.05, vec3(0.0, 8.0, 0.0)));
			if (eggWhite < distance)
			{
				scene.color = WHITE;
			}
			distance = opSmoothUnion(eggWhite, distance, 0.9);

			// float scrambled = sdRoundedCylinder(vec3(p.x, mod(p.y + 8.0, 16.0) - 8.0, p.z), q*3.0, r*0.15, r*0.05, vec3(0.0, -8.0, 0.0));
			// // scrambled = opSmoothUnion(scrambled, sdSphere(vec3(abs(p.x), mod(p.y + 8.0, 16.0) - 8.0, abs(p.z)), vec3(1.0, -8.0, 1.0), 1.0), 1.0); 
			// // scrambled = opUnion(scrambled, sdRoundedCylinder(vec3(p.x, mod(p.y, 16.0), p.z), q*3.0, r*0.15, r*0.05, vec3(0.0, 8.0, 0.0)));
			// // scrambled = opSmoothUnion(scrambled, sdSphere(vec3(abs(p.x), mod(p.y, 16.0), abs(p.z)), vec3(0.0, 8.0, 0.0), 1.0), 1.0); 
			// if (scrambled < distance)
			// {
			// 	scene.color = YELLOW;
			// }
			// distance = opSmoothUnion(scrambled, distance, 0.9);
		}
		else if (intersects(p, dir, vec3(-SEED_RAD, -SEED_AMP, -SEED_RAD), vec3(SEED_RAD, MAX_DISTANCE, SEED_RAD)))
		{
			if (increasing)
			{
				center = sdSphere(vec3(p.x, mod(p.y + 8.0, 16.0) - 8.0, p.z), spheres[2].xyz, spheres[2].w);
			}
			else
			{
				center = opSmoothUnion(center, sdSphere(vec3(p.x, mod(p.y+1.0, 16.0) - 1.0, p.z), vec3(spheres[2].x, -spheres[2].y, spheres[2].z), spheres[2].w), 1.0);
			}
			if (center < distance)
			{
				distance = center;
				scene.color = mix(BROWN, YOLK, r);
			}
		}
	}
	if (intersects(p, dir, vec3(-FLOOR_RAD, -9.0, -FLOOR_RAD), vec3(FLOOR_RAD, -8.0, FLOOR_RAD)))
	{
		/***** Floor *****/

		float boxFloor = sdBox(p, vec3(FLOOR_RAD, 0.25, FLOOR_RAD), vec3(0.0, -8.76, 0.0));
		if (boxFloor < distance)
		{
	        float ts = floor(mod((sin(p.x) + sin(p.z)) * 0.5, 2.0));
			scene.color = mix(vec3(130.0 / 255.0, 20.0 / 255.0, 20.0 / 255.0), vec3(1.0), ts);
			distance = boxFloor;
		}

		/***** Pan *****/

		float pan = sdRoundedCylinder(p, 3.5, 0.0, 0.75, vec3(0.0, -7.75, 0.0));
		pan = opSubtraction(sdRoundedCylinder(p, 3.25, 0.25, 0.75, vec3(0.0, -7.5, 0.0)), pan);
		pan = opSmoothUnion(sdCapsule(p, vec3(5.5, -7.5, 5.5), vec3(8.5, -7.5, 8.5), 1.0), pan, 1.0);
		if (pan < distance)
		{
			scene.color = vec3(0.1);
			distance = pan;
		}
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
	const float EDGE_THRESHOLD = 0.015;
	int maxMarchingSteps = 200;
	Scene scene;
	float lastDistance = float(MAX_DISTANCE);
	scene.distance = float(MAX_DISTANCE);
	for (int i = 0; i < maxMarchingSteps; i++)
	{
		scene = sceneSDF(eye + depth * rayDirection, rayDirection);
		if (scene.distance < EDGE_THRESHOLD && scene.distance > lastDistance + 0.00001)
		{
			// inside or on surface
			scene.depth = depth;
			return scene;
		}
		if(scene.distance < 0.001)
		{
			scene.depth = depth;
			return scene;
		}
		depth += scene.distance;
		lastDistance = scene.distance;
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
  vec3 V = u_Up * len * tan(radians(30.0));
  vec3 H = right * len * aspectRatio * tan(radians(30.0));
  vec3 p = u_Ref + fs_Pos.x * H + fs_Pos.y * V;
  vec3 dir = normalize(p - u_Eye);
  // vec3 color = 0.5 * (dir + vec3(1.0));
  Scene scene = rayMarch(u_Eye, dir);
  if (scene.depth < float(MAX_DISTANCE))
  {
  	vec3 color = scene.color;
  	vec4 diffuseColor = vec4(color, 1.0);
  	vec3 norm = estNorm(u_Eye + scene.depth * dir, dir);

  	vec3 lightDir = vec3(0.0, 0.5, 0.5);
	// Calculate the diffuse term for Lambert shading
	float diffuseTerm = dot(norm, normalize(lightDir));
	// if (dot(norm, -dir) <= 0.2) diffuseColor = vec4(0.0, 0.0, 0.0, 1.0);
	// Avoid negative lighting values
	diffuseTerm = clamp(diffuseTerm, 0.0f, 1.0f);
	// cartoon lighting
	if (u_ShaderMode == 1)
	{
		diffuseTerm = floor(diffuseTerm * 3.0) / 3.0;
	}

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
  